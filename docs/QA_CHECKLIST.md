# QA Checklist (100% automated contract)

ทุกข้อด้านล่าง **ตรวจได้ด้วยคำสั่ง** โดยไม่ต้องเปิดสองเครื่องด้วยมือ การทดสอบจริงบน UI ยังทำเพิ่มได้แยกตาม release process

## คำสั่งหลัก (รันครบทุกครั้งก่อน merge)

```powershell
cd D:\software_project\areyoughost
cargo test -p areyoughost_server
```

```powershell
cd D:\software_project\areyoughost\frontend
flutter test test/qa_checklist_test.dart
flutter analyze
```

> **หมายเหตุ Windows:** ถ้า `cargo test` ล้มด้วย `LNK1104 cannot open ... server-....exe` ให้ปิด process `server*.exe` / `cargo` ที่ค้าง แล้วรันใหม่

---

## C) Game phase (server authoritative)

| ข้อ | ความหมาย | เทสที่พิสูจน์ |
|-----|-----------|----------------|
| C1 | เริ่มเกมแล้ว phase เริ่มที่ Night | `state::manager::tests::qa_c1_start_game_initial_phase_is_night` |
| C2 | Night action ถูกปฏิเสธเมื่อไม่ใช่ Night | `state::manager::tests::qa_c2_night_action_rejected_when_phase_is_day` |
| C3 | โหวตกลางวันรวมเสียงครบแล้วมีการ execute / จบเกมตามกติกา | `state::manager::tests::qa_c3_unanimous_day_vote_executes_target` |
| C4 | ผู้ตายโหวต / ใช้สกิลกลางคืน / แชทกลางวันไม่ได้ | `state::manager::tests::qa_c4_dead_player_cannot_vote_action_or_day_chat` |
| C5 | Revive หมอผีคืนชีพเหยื่อที่ถูกผีฆ่าในคืนเดียวกัน | `state::manager::tests::qa_c5_witch_revive_cancels_same_night_ghost_kill` |
| C6 | แชทรวมอนุญาตเฉพาะกลางวัน | `state::manager::tests::qa_c6_global_chat_rejected_at_night` |
| C7 | ชนะฝ่ายผีเมื่อกำจัดชาวบ้านได้ (smoke) | `state::manager::tests::night_submit_ghost_kill_advances_to_day` (รวม `winnerKind` เมื่อจบที่ End) |

---

## 2) Social / Invite (สัญญา WS + ห้อง in-memory)

ใช้ `AppState::skip_persistence` ในเทสเท่านั้น — production ยังเขียน DB ตามเดิม

| ข้อ | ความหมาย | เทสที่พิสูจน์ |
|-----|-----------|----------------|
| Online = มี WS connection ลงทะเบียน | มีช่องทางส่งข้อความถึงเพื่อน | `ws::qa_tests::qa_invite_send_delivers_invite_received` |
| Private room + invite code | `create_private_room` + `invite.send` | ร่วมกับเทสด้านบน |
| `invite.sent` / `invite.received` | payload ตรงสัญญา | `ws::qa_tests::qa_invite_send_delivers_invite_received` |
| รับ invite เข้าห้อง (in-memory) | `resolve_invite` + `join_room` เหมือน `invite.accept` | `ws::qa_tests::qa_invite_code_joins_friend_in_room` |
| รายชื่อผู้เล่นตรงกัน | `room.players.len() == 2` หลัง join | `ws::qa_tests::qa_invite_code_joins_friend_in_room` |

---

## 3) Start Game

| ข้อ | เทสที่พิสูจน์ |
|-----|----------------|
| Host เริ่มได้เมื่อ ≥ 2 คน | `state::manager::tests::start_game_requires_min_two_players` (negative) + `start_game_sets_room_playing_and_runtime_created` |
| ทั้งห้องได้รับ `game.started` (ข้อความ broadcast) | `state::manager::tests::qa_game_started_broadcasts_to_two_registered_connections` |

---

## 4) Gameplay core

| ข้อ | เทสที่พิสูจน์ |
|-----|----------------|
| ตายแล้วโหวต/แชท/สกิล (ฝั่ง server) | `qa_c4` |
| Revive | `qa_c5` |
| สำรับบทจาก catalog / ไม่หลุดนอกชุดที่อนุญาต | `flutter test test/qa_checklist_test.dart` |

---

## 5) Stability

| ข้อ | เทสที่พิสูจน์ |
|-----|----------------|
| disconnect ลงทะเบียนได้โดยไม่ spawn background leave ในโหมดเทส | `state::manager::tests::qa_stability_pending_disconnect_recorded_without_background_leave` |
| Asset pipeline | `flutter test` (manifest json/bin) |
| Server panic | **พร็อกซี:** `cargo test -p areyoughost_server` (ถ้าผ่าน = ไม่ panic ในเทสชุดนี้) |

---

## 6) Static / build gate

| ข้อ | คำสั่ง |
|-----|--------|
| Flutter analyze | `flutter analyze` |
| Rust server compile | `cargo check -p areyoughost_server` |
| Rust tests | `cargo test -p areyoughost_server` |

---

## Sign-off

- Release candidate:
- Date/Time:
- Tester:
- Notes:

## Execution Log

- 2026-04-27: เพิ่ม `skip_persistence` + เทส `qa_*` และ `ws::qa_tests` เพื่อให้ checklist รันบน CI โดยไม่ต้องมี Postgres สำหรับ path เหล่านี้
- 2026-04-27: `flutter test test/qa_checklist_test.dart` — ผ่าน (deck + asset manifest)
