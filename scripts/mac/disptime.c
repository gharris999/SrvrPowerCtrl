#include <time.h>
#include <stdio.h>
#include <sys/time.h>

int main(void)
{
    struct timeval now;
    struct tm *tmp;
    char timestr[9];
    int rc;

    rc = gettimeofday(&now, 0);
    if (rc != 0) {
        perror("gettimeofday");
        return 1;
    }

    tmp = localtime(&now.tv_sec);
    if (tmp == 0) {
        perror("localtime");
        return 1;
    }

    rc = strftime(timestr, sizeof(timestr), "%H:%M:%S", tmp);
    if (rc == 0) {
        fprintf(stderr, "strftime call failed.\n");
        return 1;
    }
    printf("%s.%06ld\n", timestr, (long int) now.tv_usec);
    return 0;
}
