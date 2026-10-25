# Backlog

Designed or agreed during the 2026-10 library review, but not built yet.

## Deferred items

- **Item-editing helper.** This would replace the deleted `ViewModelItemState`. It would keep the original item, track whether it's been modified, and offer revert and save, for detail and edit screens. Decide at the end of the review whether it's worth adding.
- **Clearer deep-link warning.** When the walker can't reach a child because the model doesn't adopt `HasConnections`, say exactly that, instead of the generic "isn't handled by X" message.