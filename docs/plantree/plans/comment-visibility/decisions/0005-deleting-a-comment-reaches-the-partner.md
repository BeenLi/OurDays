# Decision 0005 — 删除评论要传到对方那边，而且不会被同步改回来

- **日期**：2026-11-25　**状态**：Accepted
- **范围**：`CommentDeletionPolicy`；`EventCommentsSection` 左滑删除；`SyncCoordinator.foregroundSync` 评论导入和补传；`CloudKitCoupleSpaceService.fetchEventCommentsByZone`

## 背景（原本的工作方式）
评论是软删除：左滑只在本地把 `EventComment.deletedAt` 设上并保存，没有把它写回 CloudKit。下一次同步导入评论时，`upsert(comments:)` 用云端的值覆盖本地字段，云端 `deletedAt` 还是空，评论就回来了；对方那边从头到尾都看得到。左滑对任何评论都可用，包括对方写的。

## 决策
- 只有作者能删自己的评论。评论记录在日程主人的 zone 里，作者写进去的，删除也写回同一个 zone（和发评论同一条路由，`CloudKitCommentWritePolicy`）。对方的评论不显示删除。
- 左滑后马上把带 `deletedAt` 的记录上传，和发评论一样是一次性的后台上传。
- 删除是单向的：导入时本地已有的 `deletedAt` 不会被云端的空值覆盖。
- 补传：同步读回评论后，如果是我删的、云端那条还没有 `deletedAt`，就再上传一次，写回读到它的那个 zone。云端追上后不再重复。从没上传成功过的评论，对方本来就没看到，不补传。

## 备选与理由
- 直接删 CloudKit 记录：旧版本的导入只认存在的记录，本地那条不会被清掉，对方旧版本上会一直显示；软删除字段旧版本已经认识（各处都过滤 `deletedAt == nil`）。
- 允许日程主人删对方的评论：评论是对方写的内容，删别人的话不合常理，也会多一个"谁说了算"的冲突。

## 影响
- 不改 schema，`deletedAt` 字段早已在 Production。旧版本收到删除会正常隐藏。
- 这个版本之前"删过"的评论，本地已被同步改回来，需要再删一次。
