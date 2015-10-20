package Plugins::SrvrPowerCtrl::lib::bQueue;
#package bQueue;

use strict;
#use warnings;

#use base 'Exporter';
#our @EXPORT = qw(push pop rpush set clear empty fill);
#our @EXPORT_OK = qw(clear createtimer empty fill fillrandom gettopbit getbottombit isempty killtimer get getbstrinvert reverse push pop rpush spin new read readbstr resize reverse set spin);

# Figure out what sort of arg is passed to bQueue->read();
use Scalar::Util qw(reftype);

our $VERSION = '1.02t';															#turbo version: no AutoRead, no BigInt, no HiRes, no Config, zero-length queues OK..


#my $bits = length( pack 'L!', 1 ) == 8 ? 64 : 32;

# bQueue->new( $nQueueLength, [$bSet], [$bUseHiResTimer], [$bAutoRead], [$nDebugLevel] ); >>>

sub new {
	my $class = shift;

	my $self = {
		_queue					=> [ ],												#Array of unsigned ints..
		_CurValue				=> 0,												#Disabled BigInt value of queue..
		_nIntSize				=> ( length( pack 'L!', 1 ) == 8 ? 64 : 32),		#This perl's integer bit size..
		_nQueueLength			=> 0,												#Number of slots in this queue..
		_nQueueSegments			=> 0,												#Number of array elements..
		_nQueueTopSegSlackMask	=> 0,												#Mask for clearing the slack space above the top bit..
		_nQueueTopSegTopBitMask => 0,												#Mask for extracting the top bit of the top segment..
		_nQueueBotSegTopBitMask => 0,												#Mask for extracting the top bit of all other segments..
		_bUseHires				=> 0,												#Use HiRes:time
		_bAutoRead				=> 0,												#Perform auto-reads...slows processing dramatically for very large queues..
		_nCreate				=> 0,												#bQueue create time
		_nLastAccess			=> 0,												#bQueue last access time
		_nLastUpdate			=> 0,												#bQueue last update time
		_nDebug					=> 0,												#bQueue debug level
		_timers					=> [ ],												#Array of timer hashes, incl timer ids, action indicators, code refs, etc..
	};

	#zero-length queues are ok..
	$self->{_nQueueLength} = shift;

	#sanity check: can't have an undefined or negative length queue..
	if (!defined($self->{_nQueueLength}) || $self->{_nQueueLength} < 1) {
		$self->{_nQueueLength}  = 0;
	}

	#Create queue full or empty..
	my $nInit = shift || 0;

	#Use hiresolution timer?
	#$self->{_bUseHires} = shift || 0;
	$self->{_bUseHires} = shift && 0;

	#Set the AutoRead flag..
	#$self->{_bAutoRead} = shift || 0;
	$self->{_bAutoRead} = shift && 0;

	#Set debug level..
	#$self->{_nDebug} = shift || 0;
	$self->{_nDebug} = shift && 0;

	#Calc the number of segments..
	$self->{_nQueueSegments} = _roundup( ($self->{_nQueueLength} / $self->{_nIntSize}) );

	#Create and initialize the segments..
	for (my $i=0; $i < $self->{_nQueueSegments}; $i++) {
		push ( @{$self->{_queue}}, ( $nInit ? ~0 : 0 ) );
	}

	#Necessary for a 0 length queue..
	if (!defined($self->{_queue}[0])) {
		push ( @{$self->{_queue}}, ( ($nInit && $self->{_nQueueLength} > 0) ? ~0 : 0 ) );
	}

	# Figure out which is the top bit in the top segment..This is the bit to discard on a push()..
	my $nTopSegTopBitIndex = ($self->{_nIntSize} - (($self->{_nIntSize} * $self->{_nQueueSegments}) - $self->{_nQueueLength})) - 1;
	$self->{_nQueueTopSegTopBitMask} = 1 << $nTopSegTopBitIndex;

	#Mask for extracting the top bit of all other segments..
	$self->{_nQueueBotSegTopBitMask} = 1 << $self->{_nIntSize} - 1;

	# Create the mask to ignore the slack bits in the top segment..i.e. the bits above our top bit..
	for (my $i = $self->{_nIntSize} - 1; $i > $nTopSegTopBitIndex; $i--) {
		$self->{_nQueueTopSegSlackMask} |= 1 << $i;
	}

	$self->{_queue}[0] &= ~$self->{_nQueueTopSegSlackMask};


	if ($self->{_bAutoRead}) {
		#Save an integer representation of the queue..
		#my $szBinary = '0b' . readbstr($self);
		#$self->{_CurValue} = oct($szBinary);
		$self->{_CurValue} = _calcvalue(readbstr($self, 1));
	}

	# timestamp the queue..
	$self->{_nCreate} = time();

	bless($self, $class);


	return $self;
}

sub _roundup {
    my $n = shift;
    return(($n == int($n)) ? $n : int($n + 1))
}


#from http://docstore.mik.ua/orelly/perl/cookbook/ch02_05.htm
sub _dec2bin {
	my $str = unpack("B32", pack("N", shift));
	$str =~ s/^0+(?=\d)//;   # otherwise you'll get leading zeros     return $str;
}

sub _quad {
    my( $str, $little )= @_;
    my $big;
    if(  ! eval { $big= unpack( "Q", $str ); 1; }  ) {
        my( $lo, $hi )= unpack "LL", $str;
        ( $hi, $lo )= ( $lo, $hi )   if  ! $little;
        $big= $lo + $hi*( 1 + ~0 );
        #if(  $big+1 == $big  ) {
        #    warn "Forced to approximate!\n";
        #}
    }
    return $big;
}


sub _calcvalue {
	my $szBStr = shift;
	my $szFormat = sprintf("B%d", length($szBStr));
	#print("\n\nFormat: $szFormat\n\n");
	#print("\n\nszBStr: $szBStr\n\n");
	#return unpack("LL", pack($szFormat, $szBStr));
	return _quad(pack($szFormat, $szBStr));
}


sub _getsegposmask {
	my $self = shift;
	my $nPos = shift || 0;
	my $nSegment;
	my $nSegPosIndex;
	my $nMask;

	#if the position lies outside of our array..
	if ( $nPos < -1 || $nPos >= $self->{_nQueueLength}) {
		return undef;
	}

	#$nPos of -1 indicates top of the queue..
	if ($nPos ==  -1) {
		#Get the bit at the top of the queue..
		$nSegment = 0;
		$nSegPosIndex = _getbitposition($self->{_nQueueTopSegTopBitMask});
		$nMask = $self->{_nQueueTopSegTopBitMask};
	} elsif ($nPos == 0) {
		#get the bit at the bottom of the queue..
		$nSegment = $self->{_nQueueSegments} - 1;
		$nSegPosIndex = 0;
		$nMask = 1;
	} else {
		#Segments: seg[0] == most significant bits; seg[$#seg] = least seg bits!!!
		$nSegment = int((($self->{_nQueueSegments}*$self->{_nIntSize})-($nPos+1))/$self->{_nIntSize});
		$nSegPosIndex = $nPos % $self->{_nIntSize};
		$nMask = 1 << $nSegPosIndex;
	}

	#if the position lies outside of our array..
	if ( $nSegment >= $self->{_nQueueSegments} || $nSegment < 0 ) {
		return undef;
	}

	return ($nSegment, $nSegPosIndex, $nMask);

}

sub _log2 {
	my $n = shift || 0;
	return log($n)/log(2);
}

sub _getbitposition {
	my $n = shift || 0;
	return log($n)/log(2);
}


# $bQueue->resize( $nQueueLength, [$bSet], [$bUseHiResTimer], [$bNoAutoRead], [$nDebugLevel] ); >>>
sub resize {
	my $self = shift || return -1;

	#zero-length queues are ok..
	$self->{_nQueueLength} = shift;

	my $nInit = shift || 0;

	#Use hiresolution timer?
	$self->{_bUseHires} = shift && 0;

	#Set the NoAutoRead flag..
	$self->{_bAutoRead} = shift || 0;

	#Set debug level..
	$self->{_nDebug} = shift && 0;

	#Clear and initialize the segments..
	@{$self->{_queue}} = ();

	$self->{_nQueueTopSegSlackMask}		= 0;	#Mask for clearing the slack space above the top bit..
	$self->{_nQueueTopSegTopBitMask} 	= 0;	#Mask for extracting the top bit of the top segment..
	$self->{_nQueueBotSegTopBitMask}	= 0;	#Mask for extracting the top bit of all other segments..
	$self->{_nCreate}					= 0;	#bQueue create time
	$self->{_nLastAccess}				= 0;	#bQueue last access time
	$self->{_nLastUpdate}				= 0;	#bQueue last update time

	#Calc the number of segments..
	$self->{_nQueueSegments} = _roundup( ($self->{_nQueueLength} / $self->{_nIntSize}) );

	for (my $i=0; $i < $self->{_nQueueSegments}; $i++) {
		push ( @{$self->{_queue}}, ( $nInit ? ~0 : 0 ) );
	}

	# Figure out which is the top bit in the top segment..This is the bit to discard on a push()..
	my $nTopSegTopBitIndex = ($self->{_nIntSize} - (($self->{_nIntSize} * $self->{_nQueueSegments}) - $self->{_nQueueLength})) - 1;

	$self->{_nQueueTopSegTopBitMask} = 1 << $nTopSegTopBitIndex;
	$self->{_nQueueBotSegTopBitMask} = 1 << $self->{_nIntSize} - 1;

	# Create the mask to ignore the slack bits in the top segment..
	for (my $i = $self->{_nIntSize} - 1; $i > $nTopSegTopBitIndex; $i--) {
		$self->{_nQueueTopSegSlackMask} |= 1 << $i;
	}

	#Mask off the top segment of the queue
	$self->{_queue}[0] &= ~$self->{_nQueueTopSegSlackMask};

	if ($self->{_bAutoRead}) {
		#Save an integer representation of the queue..
		#$self->{_CurValue} = oct('0b'. readbstr($self));
		$self->{_CurValue} = _calcvalue(readbstr($self, 1));
	}

	# timestamp the queue..
	$self->{_nCreate} = time();

	return $self;
}




# $bQueue->read( [] || [$nPosition] || [\@aPositions] || [$bString] ); >>>

sub read {
	my $self = shift || return -1;

	# bit position to test..
	my $nPosition = shift;

	# Timestamp this read..
	#$self->{_nLastAccess} = ($self->{_bUseHires} ? Time::HiRes::time : time);
	$self->{_nLastAccess} = time();

	# if not bit position, return bigint value of whole array..
	if (!defined($nPosition)) {
		#return a bigint representation of the whole array..
		#my $szBinary = '0b' . readbstr($self);
		#$self->{_CurValue} = oct($szBinary);
		#$self->{_CurValue} = oct('0b'. readbstr($self));
		$self->{_CurValue} = _calcvalue(readbstr($self, 1));
		return $self->{_CurValue};

	} elsif ( ref($nPosition) eq 'ARRAY' ) {

		# $nPosition is an array of bit positions..
		# Return an array corresponding to the bits at the positions..
		my $nPos;
		my @a;
		for (my $i=0; $i < scalar(@{$nPosition}); $i++) {
			$nPos = ${$nPosition}[$i];

			my ($nSegment, $nPosIndex, $nMask) = _getsegposmask($self, $nPos);
			if (!defined($nSegment)) {
				next;
			}

			my $bit = $self->{_queue}[$nSegment] & $nMask;
			#Binary-ize it..
			$bit = !!$bit;
			#use sprintf so that 0s show up in the array..
			push(@a, sprintf("%d", $bit));
		}

		return @a;

	#} elsif (Scalar::Util::reftype(\$nPosition) eq 'SCALAR' && substr($nPosition, 0, 2) eq '0b' ) {
	#	#$nPosition is a mask in the form of "0b000101010", etc.  Return a BigInt..
	#	if ($self->{_nDebug}) {
	#		printf("read(%s): bstring mask\n)", $nPosition);
	#	}
	#	#we've been given a string representing a binary mask..
	#	if (length($nPosition) > $self->{_nQueueLength} + 2) {
	#		$nPosition = reverse($nPosition);
	#		$nPosition = substr($nPosition, 0, $self->{_nQueueLength});
	#		$nPosition = '0b' . reverse( $nPosition );
	#	}
	#
	#	#Short-cut for small masks..
	#	if (length($nPosition)-2 <= $self->{_nIntSize}) {
	#		return $self->{_queue}[$self->{_nQueueSegments} - 1] & oct($nPosition) ;
	#	}
	#
	#	my $biMask = Math::BigInt->new($nPosition);
	#	#Put the current value into _CurValue..
	#	$self->read();
	#	return $self->{_CurValue}->band($biMask);

	} else {
		#$nPosition is a number..
		my ($nSegment, $nSegPosIndex, $nMask) = _getsegposmask($self, $nPosition);

		#Can't return a value from outside of the queue..
		if (!defined($nSegment)) {
			return undef;
		}

		my $bit = $self->{_queue}[$nSegment] & $nMask;
		#Binary-ify the return..
		$bit = !!$bit;

		return $bit;
	}
}


# $bQueue->get( [] || [$nPosition] || [\@aPositions] || [$bString] ); >>>
sub get {
	my $self = shift;
	my $nPosition = shift;
	return $self->read($nPosition);
}


# $bQueue->readbstr( [$bNoTruncate], [$bShowSegments] ); >>>
sub readbstr {
	my $self = shift || return -1;

	my $bNoTruncate = shift || 0;

	my $bShowSegments = shift || 0;

	my $szFormat =  ($bShowSegments ? "[%0$self->{_nIntSize}b]" : "%0$self->{_nIntSize}b");

	my $szBStr = '';

	for (my $i = 0; $i < $self->{_nQueueSegments}; $i++) {
		$szBStr .= sprintf($szFormat, $self->{_queue}[$i]);
	}

	# Chop off the slack from the top segment..
	if (!$bNoTruncate) {
		# Top_Slack = (Int_Size * Queue_Segments) - Queue_Length
		my $nTopChop = ($self->{_nIntSize} * $self->{_nQueueSegments}) - $self->{_nQueueLength};
		$szBStr = substr($szBStr, $nTopChop);
		if ($bShowSegments) {
			$szBStr = '[' . $szBStr;
		}
	}

	# Timestamp this read..
	$self->{_nLastAccess} = time();

	return $szBStr;
}


# $bQueue->set( [] || [$nPosition] || [@aPositions] || [$bString], [$bValue] ); >>>
sub set {
	my $self = shift || return -1;

	my $nPosition = shift;		#undef == set all bits. Numeric == set the specific bit. Array == set the bit indicated by an index value in each array entry.  "0b101010" binary string == use the string as a mask and set the bits by |= the mask.
	my $bValue = shift;			#1 (default) == set bits.  0 == clear bits..
	#my $nClear == shift || 0;	#0 (default) == preserve bits.  1 == clear entire queue..

	if (!defined($bValue)) {
		$bValue = 1;		#defaults to fill the queue..
	}
	#Binary-ify the arg..
	$bValue = !!$bValue;

	#get the current value..
	if ($self->{_bAutoRead}) {
		$self->read();
	}

	my $biOldVal = $self->{_CurValue};

	# Timestamp this write..
	$self->{_nLastUpdate} = time();

	if (!defined($nPosition)) {

		$biOldVal = $self->readbstr();

		#fill or empty the entire queue..
		for (my $i=0; $i < $self->{_nQueueSegments}; $i++) {
			$self->{_queue}[$i] = ( $bValue ? ~0 : 0 );
		}

		#Clear the slack area..
		$self->{_queue}[0] &= ~$self->{_nQueueTopSegSlackMask};

		#record the new value..
		if ($self->{_bAutoRead}) {
			$self->read();
		}

		return $biOldVal;

	} elsif ( ref($nPosition) eq 'ARRAY' ) {
		#set or clear just the bits indicated by the pos_index values in each array entry..

		# $nPosition is an array of bit positions..
		# Return an array corresponding to the bits at the positions..
		my $nPos;
		my @a;
		for (my $i=0; $i < scalar(@{$nPosition}); $i++) {
			$nPos = ${$nPosition}[$i];

			my ($nSegment, $nPosIndex, $nMask) = _getsegposmask($self, $nPos);
			if (!defined($nSegment)) {
				next;
			}

			#save the old value of the bits..
			my $bit = $self->{_queue}[$nSegment] & $nMask;
			#Binary-ize it..
			$bit = !!$bit;
			push(@a, sprintf("%d", $bit));
			#set the bit..
			if ($bValue) {
				#set the bit..
				$self->{_queue}[$nSegment] |= $nMask;
			} else {
				#clear the bit
				$self->{_queue}[$nSegment] &= ~$nMask;
			}
		}

		#Clear the slack area..
		$self->{_queue}[0] &= ~$self->{_nQueueTopSegSlackMask};

		#memorize the new value..
		if ($self->{_bAutoRead}) {
			$self->read();
		}
		return @a;

	#} elsif (Scalar::Util::reftype(\$nPosition) eq 'HASH' && defined($nPosition->{value}) ) {
	#	#$nPosition is a BigInt...
	#	print("bQueue->set(BigInt); not supported yet..\n");
	#	return $biOldVal;

	} elsif (Scalar::Util::reftype(\$nPosition) eq 'SCALAR' && substr($nPosition, 0, 2) eq '0b' ) {
		#$nPosition is a mask in the form of "0b000101010", etc.
		my $szOldQueue = readbstr($self);

		#we've been given a string representing a binary mask..make sure it's not too long..
		if (length($nPosition) > $self->{_nQueueLength} + 2) {
			$nPosition = reverse($nPosition);
			$nPosition = substr($nPosition, 0, $self->{_nQueueLength});
			$nPosition = '0b' . reverse( $nPosition );
		}

		#trim off the leading '0b'
		$nPosition = substr($nPosition, 2);
		#reverse the string
		$nPosition = reverse($nPosition);

		my $szSegMask = '';

		for (my $i = ($self->{_nQueueSegments}-1); $i >= 0; $i--) {
			#If we've run out of mask to process..
			next if !length($nPosition);

			#break the segment mask
			$szSegMask = substr($nPosition, 0, $self->{_nIntSize});
			#prepend a '0b' and reverse the seg mask
			$szSegMask = '0b' . reverse($szSegMask);

			if ($bValue) {
				#set the bits..
				@{$self->{_queue}}[$i] |= oct($szSegMask);
			} else {
				#clear the bits..
				@{$self->{_queue}}[$i] &= ~oct($szSegMask);
			}

			if ( length($nPosition) >= $self->{_nIntSize} ) {
				$nPosition = substr($nPosition, $self->{_nIntSize} );
			}

		}

		#Clear the slack area..
		$self->{_queue}[0] &= ~$self->{_nQueueTopSegSlackMask};

		#Memorize the new value..
		#record the new value..
		if ($self->{_bAutoRead}) {
			$self->read();
		}
		return $szOldQueue;

	} else {

		my ($nSeg, $nPosIndex, $nMask) = _getsegposmask($self, $nPosition);

		if (!defined($nSeg)) {
			return undef;
		}

		#save the bit..
		my $bit = $self->{_queue}[$nSeg] & $nMask;
		#Binary-ize it..
		$bit = !!$bit;

		#set or clear the bit..
		if ($bValue) {
			$self->{_queue}[$nSeg] |= $nMask;
		} else {
			$self->{_queue}[$nSeg] &= ~$nMask;
		}

		#Clear the slack area..
		$self->{_queue}[0] &= ~$self->{_nQueueTopSegSlackMask};

		#memorize the new value..
		if ($self->{_bAutoRead}) {
			$self->read();
		}
		return $bit;
	}


}


# $bQueue->fill(); >>>
sub fill {
	my $self = shift;
	return set($self, undef, 1);
}



# $bQueue->isempty( [$bTopDown] ); >>>
sub isempty {
	my $self = shift || return -1;
	my $topdown = shift || 0;
	#my $bi = $self->read();
	#return $bi->is_zero();
	#return !$bi;

	# Timestamp this read..
	$self->{_nLastAccess} = time();

	if ($topdown) {
		for (my $i = 0; $i < $self->{_nQueueSegments}; $i++) {
			if ($self->{_queue}[$i]) {
				return 0;
			}
		}

	} else {
		#search from bottom up..
		for (my $i = $self->{_nQueueSegments} - 1; $i > -1 ; $i--) {
			if ($self->{_queue}[$i]) {
				return 0;
			}
		}
	}

	return 1;
}

#If no bits are set, returns -1
sub getbottomsetbitindex {
	my $self = shift || return -1;
	my $index = 0;
	my $test;

	for (my $i = $self->{_nQueueSegments} - 1; $i > -1 ; $i--) {
		$test = 1;
		for (my $j = 0; $j < $self->{_nIntSize}; $j++) {
			if ($self->{_queue}[$i] & $test) {
				return $index;
			}
			$test <<= 1;
			$index++;
		}
	}

	return -1;
}



# $bQueue->push( [$nNewBottomBit] ); >>>

sub push {
	my $self = shift || return -1;

	# Timestamp this write..
	$self->{_nLastUpdate} = time();

	my $nNewBottomBit = shift || 0;
	#Binary-ify the arg..
	$nNewBottomBit = !!$nNewBottomBit;

	#A zero-length queue discards whatever was pushed in..
	if ($self->{_nQueueLength} == 0) {
		return $nNewBottomBit;
	}

	my $nSegDiscardBit;

	#top queue segment is *especial* because of the slack space..
	my $nTopDiscardBit = $self->{_queue}[0] & $self->{_nQueueTopSegTopBitMask};
	#Binary-ify it..
	$nTopDiscardBit = !!$nTopDiscardBit;

	#if we have a queue of more than one segment..
	# Work from the top down...
	for (my $i = 0; $i < $self->{_nQueueSegments}; $i++) {
		#save the top bit..
		$nSegDiscardBit = $self->{_queue}[$i] & ( $i ? $self->{_nQueueBotSegTopBitMask} : $self->{_nQueueTopSegTopBitMask} ) ;
		$nSegDiscardBit = !!$nSegDiscardBit;
		#push the queue segment..
		$self->{_queue}[$i] <<= 1;
		#set the discarded bit on the next higher seg..
		if ($i) {
			$self->{_queue}[$i-1] |= $nSegDiscardBit;
		}
	}

	#set the new bottom bit..
	$self->{_queue}[$self->{_nQueueSegments} - 1] |= $nNewBottomBit;

	#Mask off the top segment of the queue
	$self->{_queue}[0] &= ~$self->{_nQueueTopSegSlackMask};

	return 	$nTopDiscardBit;
}




# $bQueue->getbottombit(); >>>
sub getbottombit {
	my $self = shift || return -1;

	#A zero-length queue is always empty..
	if ($self->{_nQueueLength} == 0) {
		return 0;
	}

	my $botBit = $self->{_queue}[$self->{_nQueueSegments} - 1] & 1;
	return $botBit;
}



1;
__END__
