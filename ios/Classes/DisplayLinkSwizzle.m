#import <QuartzCore/QuartzCore.h>
// Legacy linkage symbols only. Automatic process-wide interception was removed.
void RRSetOverrideMaxRate(float rate) {}
float RRGetOverrideMaxRate(void) { return 0; }
void RRBypassDisplayLink(CADisplayLink *link) {}
void RRApplyOverrideToTrackedLinks(void) {}
