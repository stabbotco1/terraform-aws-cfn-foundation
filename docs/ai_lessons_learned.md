# AI Agent Lessons Learned

## Verification & Testing

1. **Single verification is insufficient** - Need 2-3 independent verification methods minimum
2. **Happy path ≠ complete testing** - Must test idempotency, errors, edge cases, recovery
3. **Overconfidence is dangerous** - Agent claimed success after minimal testing
4. **State comparison required** - Must verify before/after states, not just final state
5. **Tag-based queries reveal truth** - Found orphaned CloudTrail bucket via tags that stack queries missed

## Implementation Quality

1. **"No updates" is valid CloudFormation state** - CloudFormation correctly reports when nothing changed; script must handle gracefully
2. **Orphaned resources are real** - DeletionPolicy: Retain creates orphans that need detection
3. **Testing infrastructure ≠ production** - TESTING_FORCE_STACK_UPDATE flag enables forced updates for testing only
4. **Timestamps can force updates** - But it's bad practice for production (good for testing)
5. **Error handling was incomplete** - Script had `set -euo pipefail` but didn't catch "No updates" error

## Architecture Decisions

1. **Separation of concerns** - list-deployed-resources.sh lists orphans; destroy.sh destroys stack resources only
2. **Informational vs actionable** - Orphan detection should inform, not prescribe actions
3. **Naming patterns enable detection** - Consistent naming (`{resource}-{account}-{region}`) enables high-confidence orphan detection
4. **Multiple detection methods** - Naming + tags + existence + stack exclusion = 95%+ confidence
5. **Termination protection is critical** - Prevents accidental deletion of foundational infrastructure

## Process Improvements

1. **Verification requirements document** - Added explicit testing scope, methods, and reporting requirements to ai_context.md
2. **Trust but verify principle** - Single source insufficient, two acceptable, three+ ideal
3. **Report what wasn't tested** - Surfacing and reporting gaps more valuable than false confidence
4. **Commit permission matters** - Explicit permission to commit enables faster iteration
5. **Git state blocks testing** - Prerequisites check prevents testing with uncommitted changes

## Technical Discoveries

1. **Stack updates preserve resources** - Removing conditional resources from template deletes them (except Retain policy)
2. **Parameter changes trigger updates** - Adding LastDeploymentTimestamp parameter enables testing mode
3. **Bash variable precedence** - .env file loads early, environment variables can override
4. **Resource ARN vs ID mismatch** - Initial orphan detection failed because comparing ARNs to resource IDs

## Meta-Lessons

1. **Time investment in context pays off** - Most of session was context-setting, but enabled better and faster work
2. **Guardrails prevent waste** - Verification requirements catch incomplete testing sooner
3. **Iterative refinement works** - Multiple rounds of testing consistently reveals issues faster
4. **Documentation of process matters** - This lessons learned list captures knowledge for future sessions
