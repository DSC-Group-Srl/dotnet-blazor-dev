# Architecture: <Feature Name>

**Date**: YYYY-MM-DD
**Complexity**: [LOW/MEDIUM/HIGH]
**Author**: blazor-architect
**Status**: [Proposed/Approved/Implemented]

> **Skills applied**: skill-x, skill-y
> *(List only skills actually loaded. Remove this line if none were loaded.)*

## Executive Summary

## Business Context
### Problem Statement
### Success Criteria

## Architectural Design
### Layering (Client / Server / Shared / Shared.Server / ServiceFn)
### Data Model & Access Strategy
### Multi-Tenancy Model
### UI Components
### Integration Points
### Security Model
### Performance Considerations
### Testing Strategy

## Implementation Phases

## Technical Decisions

## Dependencies

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|

## Deployment Plan

## Next Steps

**Architecture Approved — Create Technical Specification**
```
/blazor-spec-create
Create spec for {req_name}. Read requirements/{req_name}/{req_name}.architecture.md
```

After spec is created:
```
agent "blazor-dev:blazor-conductor"
Implement {req_name}. Contracts in requirements/{req_name}/
```

For LOW complexity (no architect needed):
```
agent "blazor-dev:blazor-developer"
Implement {req_name}. Read requirements/{req_name}/{req_name}.spec.md
```
