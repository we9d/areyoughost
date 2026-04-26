# AreYouGhost - Development Handoff (26 Apr 2026)

เอกสารนี้เขียนเพื่อให้เพื่อนในทีมรับงานต่อได้ทันที โดยไม่ต้องไล่อ่านแชทย้อนหลังทั้งหมด

---

## 1) ภาพรวมโปรเจกต์ (ฉบับใช้งานจริง)

- Repository: `areyoughost`
- Branch ปัจจุบันที่ใช้งาน: `Network-socket`
- Stack หลัก:
  - Frontend: Flutter (Windows desktop)
  - Backend: Rust (server + core)
  - DB: PostgreSQL (Supabase path เป็นหลัก)
  - Realtime: WebSocket (`WsService`)
- โครงที่ใช้งานจริงฝั่ง Flutter:
  - Entry: `frontend/lib/main.dart`
  - หน้า Home: `frontend/lib/ui/home/home.dart`
  - โหมดเกม: `frontend/lib/ui/game/mode_select_screen.dart`
  - ห้อง/เชิญเพื่อน: `frontend/lib/ui/Invite_friend/*`, `frontend/lib/ui/widgets/icons/mail_noti_icon.dart`
  - หน้าระหว่างเกม: `frontend/lib/ui/game/game_screen.dart`

---

## 2) สิ่งที่พัฒนาไปล่าสุด (สำคัญมาก)

ส่วนนี้คือสิ่งที่เปลี่ยนจริงและส่งผลกับ flow ปัจจุบัน

### 2.1 Invite / Mail flow

- ไอคอนจดหมายถูกปรับให้เป็น flow ตามสถานะ:
  - ไม่มี invite: ไอคอนปกติ + กดแล้ว popup "ไม่มีคำเชิญชวน"
  - มี invite: ไอคอนมีจุดแดง + กดแล้ว popup รับ/ปฏิเสธ
- ปิดการเปิด popup invite แบบอัตโนมัติจาก event `invite.received` (เหลือแค่ขึ้น badge)
- ไฟล์หลัก:
  - `frontend/lib/main.dart`
  - `frontend/lib/ui/widgets/icons/mail_noti_icon.dart`
  - `frontend/lib/ui/widgets/icons/mail-icon.dart`

### 2.2 Invitee room screen ให้เหมือน host

- ผู้ถูกเชิญเข้าห้องจะไปหน้าเดียวกับ host (`HostRoomScreen`) เพื่อให้ UI เหมือนกัน
- แต่ซ่อนเฉพาะ:
  - รหัสเชิญ
  - ปุ่มเริ่มเกม
- ยังมีปุ่มเชิญเพื่อนตาม requirement
- ทำผ่านพารามิเตอร์ `showHostControls` ใน:
  - `frontend/lib/ui/Invite_friend/Invite_host.dart`
- เปลี่ยน route จาก popup รับคำเชิญใน:
  - `frontend/lib/ui/widgets/icons/mail_noti_icon.dart`

### 2.3 สถานะออนไลน์ขึ้นตั้งแต่เปิดแอป

- เมื่อมี session/token แล้ว แอปจะพยายาม connect WS ตั้งแต่ `checkLoginStatus()`
- หลัง login สำเร็จ จะ connect WS ทันทีอีกครั้งเพื่อให้ presence ขึ้นไว
- จุดหลัก:
  - `frontend/lib/services/auth_service.dart`
  - `frontend/lib/services/ws_service.dart`

### 2.4 ผู้เล่นตาย = ดูได้อย่างเดียว จนกว่าจะถูกชุบ

- ผู้เล่นที่ตายถูกบล็อก:
  - โหวต
  - ใช้สกิล
  - แชท
- ถ้าถูกชุบจะกลับมา alive และรูปกลับเป็นผู้เล่นตาม grid ปกติ
- จุดหลัก:
  - `frontend/lib/ui/game/game_screen.dart`
  - `frontend/lib/ui/game/widgets/chat_input_row.dart`
  - `frontend/lib/ui/game/widgets/player_grid_day.dart`
  - `frontend/lib/ui/game/widgets/player_grid_night.dart`

### 2.5 แก้บทซ้ำ (เช่น หมอผีดำซ้ำ)

- ปรับการสร้าง/แจกสำรับให้ไม่วนบทพิเศษซ้ำจาก modulo
- ถ้าจำนวนบทไม่พอ จะเติม `ชาวบ้าน`
- เพิ่ม helper deck กลาง:
  - `frontend/lib/ui/game/role_deck.dart`
- ใช้ใน:
  - `frontend/lib/ui/game/random_role_screen.dart`
  - `frontend/lib/ui/game/game_screen.dart`

### 2.6 แก้การ์ดผู้เล่นช่องแรกกว้างไม่เท่าคนอื่น

- แก้ `Stack` ให้ `fit: StackFit.expand` ใน grid กลางวัน/กลางคืน
- ไฟล์:
  - `frontend/lib/ui/game/widgets/player_grid_day.dart`
  - `frontend/lib/ui/game/widgets/player_grid_night.dart`

### 2.7 ปัญหา build ที่เจอล่าสุดบน Windows

- เคส asset not found เคลียร์ด้วย clean/build ใหม่
- เคส Visual C++ `C1041` (.pdb lock) ต้อง kill process build เก่าก่อนรันใหม่

---

## 3) สถานะ repository ตอนนี้

ตอนนี้มีไฟล์แก้เยอะมากทั้ง `core`, `server`, `frontend` และมีไฟล์ใหม่หลายตัว (รวม migration)

ข้อแนะนำก่อนรับงานต่อ:

1. อย่ารีเซ็ตทั้ง repo ทิ้งทันที
2. ให้แยกงานเป็นกลุ่ม (frontend/gameplay, backend/rules, invite/social, migration)
3. รัน test/verify ทีละกลุ่มก่อน commit

---

## 4) วิธีเตรียมเครื่องสำหรับ dev ต่อ (ละเอียด)

## 4.1 Prerequisites

ติดตั้งให้ครบก่อน:

- Flutter SDK (stable)
- Rust toolchain (stable)
- Visual Studio 2022 + workload `Desktop development with C++`
- Git
- (ถ้าต้องใช้ local DB) Docker Desktop

เช็คเวอร์ชัน:

```powershell
flutter --version
rustc --version
cargo --version
```

## 4.2 Clone + เปิดโปรเจกต์

```powershell
git clone <repo-url>
cd areyoughost
```

## 4.3 ตั้งค่า env

```powershell
Copy-Item .env.example -Destination .env
```

จากนั้นแก้ค่าที่จำเป็น:

- `DATABASE_URL`
- `JWT_SECRET`
- ค่า host/port ตาม environment ทีม

## 4.4 เตรียม Flutter

```powershell
cd frontend
flutter pub get
```

ถ้าต้องใช้ endpoint แบบปรับได้:

- ดู `frontend/app_config.example.json`
- สร้าง/คัดลอกเป็น config ที่ runtime ใช้จริง (ตาม flow ทีม)

## 4.5 เตรียม Rust/backend

ที่ root:

```powershell
cargo build --workspace
```

รัน server:

```powershell
cargo run -p areyoughost_server
```

## 4.6 รัน frontend

```powershell
cd frontend
flutter run -d windows
```

---

## 5) Development workflow ที่แนะนำให้ทีม

## 5.1 แยกงานเป็น 4 stream

1. Gameplay/UI (`frontend/lib/ui/game/*`)
2. Invite/Friends (`frontend/lib/ui/widgets/icons/*`, `services/friend_service.dart`, routes ฝั่ง server)
3. Game rules ฝั่ง Rust (`core/src/game_logic/*`)
4. DB schema/migrations (`core/migrations/*`)

## 5.2 กติกาก่อน push

- Flutter:
  - `flutter analyze`
  - run app manual smoke test
- Rust:
  - `cargo fmt --all`
  - `cargo test --workspace` (อย่างน้อย package ที่แตะ)
- DB:
  - migration ใหม่ต้อง rollback/re-run ได้

## 5.3 Smoke test ขั้นต่ำ (ต้องผ่านทุกครั้ง)

1. เปิดแอปได้ ไม่มี asset error
2. login แล้วเพื่อนเห็น online
3. สร้างห้อง + invite friend ได้
4. ฝั่งโดน invite เห็น badge จดหมายแดง และกดรับเข้าได้
5. เกมเริ่มแล้ว:
   - ผู้เล่นตายกดสกิล/โหวต/แชทไม่ได้
   - ชุบแล้วกลับมา alive ได้

---

## 6) จุดที่ต้องระวัง (Known Issues / Risks)

## 6.1 Windows build lock (C1041 .pdb)

อาการ:

- build fail ด้วย `cannot open program database ... .pdb`

วิธีแก้เร็ว:

```powershell
cd frontend
Get-Process | Where-Object { $_.ProcessName -in @('cl','mspdbsrv','msbuild','flutter_tester') } | Stop-Process -Force -ErrorAction SilentlyContinue
flutter clean
flutter pub get
flutter run -d windows
```

## 6.2 Asset หาไม่เจอเป็นบางรอบ

แม้ไฟล์อยู่จริง อาจเกิดจาก cache/build state

```powershell
cd frontend
flutter clean
flutter pub get
flutter run -d windows
```

## 6.3 โค้ด WIP เยอะ

repo ยังมีการแก้ค้างจำนวนมากในหลายโมดูล ควรหลีกเลี่ยง commit รวมทุกอย่างทีเดียว

---

## 7) ไฟล์สำคัญที่ควรรู้ก่อนแก้

## Frontend - Core flow

- `frontend/lib/main.dart` - app bootstrap, invite stream listener
- `frontend/lib/services/auth_service.dart` - login/session/ws connect
- `frontend/lib/services/ws_service.dart` - websocket lifecycle + reconnect
- `frontend/lib/ui/home/home.dart` - home icons/actions
- `frontend/lib/ui/widgets/icons/mail_noti_icon.dart` - invite badge + accept/reject popup
- `frontend/lib/ui/Invite_friend/Invite_host.dart` - host/invitee room UI หลัก
- `frontend/lib/ui/game/game_screen.dart` - day/night, vote, skills, alive/dead state
- `frontend/lib/ui/game/role_deck.dart` - role deck generation

## Backend/Core - Rules

- `core/src/game_logic/night_resolver.rs`
- `core/src/game_logic/win_checker.rs`
- `core/src/game_logic/day_resolver.rs` (ไฟล์ใหม่)
- `core/src/game_logic/vote_resolver.rs` (ไฟล์ใหม่)
- `core/src/game_logic/rules_locked.rs` (ไฟล์ใหม่)
- `core/src/game_logic/gm_spec.rs` (ไฟล์ใหม่)

## Database / API

- `core/migrations/20260424113000_seed_roles_from_cn321_pdf.sql`
- `server/src/routes/friends.rs` (ไฟล์ใหม่)
- `server/src/routes/players.rs` (ไฟล์ใหม่)
- `server/src/routes/roles.rs` (ไฟล์ใหม่)

---

## 8) แผนงานต่อที่แนะนำ (1-2 สัปดาห์)

## Sprint A (เสถียรภาพ)

- [ ] แยก/cleanup `.dart_tool`, `build`, ไฟล์ generated ที่ไม่ควร track
- [ ] ตรึง flow invite/friend ด้วย test case จริง 2 เครื่อง
- [ ] ทำ checklist regression ของ game phase day/night

## Sprint B (game rule parity)

- [ ] review rule V7/V9/G14/S16 ให้ตรง DB + frontend + core
- [ ] เพิ่ม test ฝั่ง rust สำหรับ tie vote / revive / passive skills
- [ ] ทำ mapping role/skill image ให้ครบจาก catalog เดียว

## Sprint C (ทีมทำงานต่อได้เร็ว)

- [ ] ทำ `docs/QA_CHECKLIST.md`
- [ ] ทำ `docs/RELEASE_RUNBOOK.md`
- [ ] เพิ่ม script dev one-command (`scripts/dev.ps1`) สำหรับเปิด server+client

---

## 9) คำสั่งใช้งานประจำ (คัดลอกได้เลย)

## 9.1 รัน server

```powershell
cargo run -p areyoughost_server
```

## 9.2 รัน Flutter Windows

```powershell
cd frontend
flutter run -d windows
```

## 9.3 วิเคราะห์โค้ด Flutter

```powershell
cd frontend
flutter analyze
```

## 9.4 Rust test

```powershell
cargo test --workspace
```

## 9.5 ล้าง build กรณีเพี้ยน

```powershell
cd frontend
flutter clean
flutter pub get
```

---

## 10) หมายเหตุสำหรับคนรับไม้ต่อทันที

ถ้าคุณเพิ่งเปิดงานวันนี้ ให้ทำตามนี้ตามลำดับ:

1. `git status` ดูภาพรวมก่อน
2. เปิด `docs/DEV_HANDOFF_2026-04-26.md` (ไฟล์นี้)
3. รัน backend + frontend ให้ขึ้นทั้งคู่
4. ทดสอบ 5 เคส smoke test (หัวข้อ 5.3)
5. ค่อยเริ่มแก้ issue ถัดไป

ถ้าจะเริ่มจาก social/invite ให้เริ่มที่:

- `main.dart`
- `mail_noti_icon.dart`
- `Invite_host.dart`
- `friend-icon.dart`

ถ้าจะเริ่มจาก gameplay ให้เริ่มที่:

- `game_screen.dart`
- `player_grid_day.dart`
- `player_grid_night.dart`
- `role_deck.dart`

---

## 11) เอกสารที่เกี่ยวข้อง

- `README.md`
- `docs/DEVELOPMENT.md`
- `docs/ARCHITECTURE.md`
- `docs/PROTOCOL.md`
- `docs/REMOTE_DEMO_TUNNEL.md`

