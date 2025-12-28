# IAM Permissions Strategy

## Foundation Role Design Philosophy

The `DeploymentRolesRole` created by this foundation uses `IAMFullAccess` managed policy by design, not oversight. This document explains the reasoning behind this architectural decision.

## Why Broad Permissions Are Necessary

### The IAM Factory Pattern

The deployment roles project acts as an "IAM factory" that creates roles for downstream projects. These downstream projects have diverse and evolving requirements:

- **Multi-service projects**: May need permissions across EC2, RDS, Lambda, S3, etc.
- **Evolving requirements**: New features require new permissions over time
- **Unknown future needs**: Cannot predict all services a project might eventually use

### Operational Constraints

**Restrictive permissions would create operational bottlenecks:**

1. **Constant updates required**: Each new downstream project or feature would require updating the foundation role
2. **Union of all permissions**: The role would eventually need the union of all possible downstream permissions anyway
3. **Deployment failures**: Restrictive permissions cause deployment failures that require emergency fixes
4. **Operational overhead**: Managing granular permissions across multiple projects becomes unmanageable

## Industry Standard Approach

### Bootstrap vs. Runtime Permissions

Modern IAM strategies distinguish between two permission tiers:

1. **Bootstrap roles** (this foundation): Broad permissions for infrastructure setup
2. **Runtime roles** (downstream projects): Refined permissions based on actual usage

### Permission Refinement Process

The standard approach for downstream roles:

1. **Start permissive**: Deploy with broad permissions to ensure functionality
2. **Collect usage data**: Use CloudTrail and IAM Access Analyzer to track actual API calls
3. **Analyze unused access**: Identify permissions that are never used
4. **Automated tightening**: Use tools to create least-privilege policies based on real usage
5. **Regular reviews**: Periodic access reviews to remove stale permissions

## Security Through Observability

Rather than restricting the foundation role, security comes from:

- **Strong authentication**: OIDC with GitHub Actions prevents credential exposure
- **Comprehensive logging**: CloudTrail captures all API calls for audit
- **Access analysis**: IAM Access Analyzer identifies unused permissions
- **Automated monitoring**: Alerts on unusual access patterns
- **Regular reviews**: Scheduled access reviews and policy optimization

## Alternative Approaches (And Why They Fail)

### Permission Boundaries
- **Problem**: Still requires knowing all possible actions upfront
- **Limitation**: Doesn't solve the operational overhead problem

### Service-Specific Roles
- **Problem**: Breaks down when projects span multiple AWS services
- **Limitation**: Creates artificial constraints on project architecture

### Just-in-Time Elevation
- **Problem**: Adds approval workflows and operational complexity
- **Limitation**: Slows down deployments and emergency responses

## Conclusion

The `IAMFullAccess` policy for the foundation deployment role is an intentional architectural decision that:

- Enables operational efficiency and deployment reliability
- Follows industry best practices for bootstrap infrastructure
- Allows security optimization at the appropriate layer (downstream roles)
- Prevents operational bottlenecks that would require constant maintenance

The real security boundary is established through strong authentication, comprehensive monitoring, and automated policy optimization in the roles that this foundation enables.
