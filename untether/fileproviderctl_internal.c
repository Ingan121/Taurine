#include <stdio.h>
#include <unistd.h>

#define STAGE_TWO "/Applications/Taurine.app/TaurineHeadless"

int main() {
    // KFD has a low success rate on really early boot, so wait for a few seconds before jailbreaking
    // no delay to 3s delay: almost impossible. I had no success with these values
    // 5s-8s delay: success rate is low but not that impossible
    sleep(10);
    execl(STAGE_TWO, STAGE_TWO, NULL);
}
