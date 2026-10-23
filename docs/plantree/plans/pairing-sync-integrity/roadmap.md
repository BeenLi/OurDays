# Roadmap — pairing-sync-integrity

## Done
- ✅ **#4**（2026-10-21）删除"两人锁"的静默移除；多出的参与者一律进配对冲突，由用户在弹窗里选保留谁；保留新人时清掉旧伴侣的备注名、头像、配对日期等本地状态。→ [0001](decisions/0001-conflict-alert-not-silent-lock.md)
- ✅ **#20**（2026-10-23）根记录只在 ownerMemberID 不同时写入；MemberProfile 只写有变化的 key，只有别的 key 变了才更新 `updatedAt`；没有 changedKeys 的记录跳过保存；挂父记录的操作幂等。→ [0002](decisions/0002-save-shared-records-only-on-change.md)
- ✅ **#22**（2026-10-23）首次同步在本机还没有任何"已上传"的影子记录之前，读自己 private zone 的 EventMirror，把本地日历里已不存在的打墓碑；「继续使用现有 iCloud 数据」顺带取回配对日期、昵称、头像；三处文案不再说"重装前请先解除配对"。冒烟新增 step 12。→ [0003](decisions/0003-reinstall-recovers-from-icloud.md)
- ✅ **#23**（2026-10-23）解除配对（以及配对冲突里选择保留新人）时删掉 private zone 里非我写的评论、全部邀请与历史申请记录，并清同样的本地缓存；导入时过滤"另一方既不是我也不是现任"的记录。→ [0004](decisions/0004-ex-partner-data-purged-and-filtered.md)

## Verify
- ✅ #22 冒烟 step 12 通过（2026-10-23）。
- ✅ #20 用两模拟器观察：同步后不再出现对方的连环静默推送。
- ⏳ #4 冲突弹窗、#23 换人重配：需要第三个 iCloud 账号，未跑。

## Deferred
- 解除配对目前是单边的：只删我的 CKShare 和我 zone 里的前任记录，不替对方退出他的分享；对方那边由他自己的解除配对处理。
