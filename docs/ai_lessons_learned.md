# AI Agent Lessons Learned

## One-Line Summary

Removed CloudTrail from infrastructure project, added testing support and orphan detection, while learning that AI agents require explicit verification requirements, multi-source validation, and clear authority boundaries to avoid overconfident incomplete work.

## Context & Communication

1. **Explicit instructions prevent assumptions** - Agent assumed X's were redactions rather than asking
2. **Word count matters** - Took ~162 words across 3 messages to correct presumptuous behavior
3. **Authority must be explicit** - Agent offered to fix things without being asked
4. **Context files are essential** - Created `docs/ai_context.md` to encode behavioral expectations
5. **Markdown compliance matters** - DavidAnson linting rules should be followed from start

## Verification & Testing

1. **Single verification is insufficient** - Need 2-3 independent verification methods minimum
2. **Happy path ≠ complete testing** - Must test idempotency, errors, edge cases, recovery
3. **Overconfidence is dangerous** - Agent claimed success after minimal testing
4. **State comparison required** - Must verify before/after states, not just final state
5. **Tag-based queries reveal truth** - Found orphaned CloudTrail bucket via tags that stack queries missed

## Implementation Quality

1. **"No updates" is valid state** - CloudFormation correctly reports when nothing changed; script must handle gracefully
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
3. **Report what wasn't tested** - Honesty about gaps more valuable than false confidence
4. **Commit permission matters** - Explicit permission to commit enables faster iteration
5. **Git state blocks testing** - Prerequisites check prevents testing with uncommitted changes

## Technical Discoveries

1. **CloudFormation conditions work** - `Condition: EnableCloudTrail` properly removed resources
2. **Stack updates preserve resources** - Removing conditional resources from template deletes them (except Retain policy)
3. **Parameter changes trigger updates** - Adding LastDeploymentTimestamp parameter enables testing mode
4. **Bash variable precedence** - .env file loads early, environment variables can override
5. **Resource ARN vs ID mismatch** - Initial orphan detection failed because comparing ARNs to resource IDs

## Remaining Gaps

1. **destroy.sh untested** - Don't know if it handles current state correctly
2. **Fresh deployment untested** - Would require destroying existing stack
3. **ROLLBACK_COMPLETE recovery untested** - Error recovery path not validated
4. **Testing mode not fully validated** - Git state requirements prevented complete testing
5. **Orphaned bucket cleanup undefined** - No automated way to clean up orphans (by design)

## Meta-Lessons

1. **Time investment in context pays off** - Most of session was context-setting, but enabled better work
2. **Guardrails prevent waste** - Verification requirements would have caught incomplete testing earlier
3. **Iterative refinement works** - Multiple rounds of testing revealed issues
4. **Explicit scope prevents scope creep** - "Remove CloudTrail" stayed focused after initial corrections
5. **Documentation of process matters** - This lessons learned list captures knowledge for future sessions
