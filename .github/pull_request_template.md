## Summary
<!-- What changed and why. Link the issue. -->

## Evidence
<!-- Documentation, specifications, tests or device measurements that support this change. -->

## Tests
<!-- Tests added or changed, and the devices used for any on-device check. -->

## Security self-check
<!-- Answer only if this touches metadata, signing, files or permissions; otherwise write "n/a". -->
- Adds network access? 
- Stores or caches anything on the device? 
- Logs anything? 
- Changes what is written to a saved file? 
- Changes how photos are signed? 

## Checklist
- [ ] Tests cover the change, and coverage does not drop.
- [ ] No network access, analytics or third-party SDK added.
- [ ] No new metadata written, or the metadata tests are updated.
- [ ] `CHANGELOG.md` updated under "Unreleased", if users would notice the change.
- [ ] Every commit is signed off (`git commit -s`).
