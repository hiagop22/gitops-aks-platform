## What changed
<!-- Describe what this PR changes -->

## Affected components
<!-- Check all that apply -->
- [ ] Terraform (bootstrap)
- [ ] Platform components (cluster-wide)
- [ ] Workloads (app manifests)
- [ ] Bootstrap/ApplicationSets
- [ ] Documentation

## Impact
- [ ] Breaking change (requires manual intervention)
- [ ] New feature (fully automated)
- [ ] Bug fix
- [ ] Performance improvement

## Validation performed
<!-- How did you test this? -->
- [ ] `kubectl kustomize` validated
- [ ] `kubectl apply --dry-run=server` run
- [ ] Terraform plan reviewed (if TF changes)
- [ ] Verified in dev environment

## Reviewer Notes
<!-- Any specific areas to focus on? -->
- [ ] Security implications reviewed
- [ ] Resource limits set appropriately
- [ ] No secrets exposed

## Checklist
- [ ] CODEOWNERS updated if changing access patterns
- [ ] No secrets committed
- [ ] All overlays updated for affected environments
- [ ] Documentation updated (if needed)
- [ ] Tested in nonprod environment

## Related Issues
<!-- Link to issues this PR resolves -->
Closes #

/label ~"gitops"