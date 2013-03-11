# TODO

## Next

- Delete Gist
- Modify Gist Description

## Suggestions

- Use `TM_DOCUMENT_UUID` as primary cache key and fallback on `TM_FILEPATH`. This should allow dealing with unsaved documents without needing to actually save them.
- Fetching a gist should pipe the data to `mate` so that we get an unsaved document. File type and display name can be set via options, but presently there is no `--uuid`, which would be required to allow later updating the fetched gist (this should be added to mate).
- ✓ Wrap network IO in `TextMate.call_with_progress` (from `#{ENV['TM_SUPPORT_PATH']}/lib/progress`).

## Done

- ✓ Create Gist from Selection (but cannot cache it)
- ✓ Add file to Gist
