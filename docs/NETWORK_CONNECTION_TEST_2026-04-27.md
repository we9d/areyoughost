# เอกสารทดสอบระบบ AreYouGhost (ฉบับละเอียด)

วันที่/เวลาเอกสาร: 2026-04-27 18:50 (UTC+7)  
ผู้จัดทำ: Cursor Agent + ผู้ทดสอบ  
ขอบเขต: Test Case ครอบคลุมทั้งระบบ (Functional, Network, Reconnect, Gameplay, Stability, Build, Security เบื้องต้น)

---

## 1) วัตถุประสงค์การทดสอบ

- ตรวจสอบความถูกต้องของระบบตั้งแต่เริ่มเปิดแอปจนจบเกม
- ตรวจสอบกรณีเครือข่ายหลุด/กลับมาเชื่อมต่อใหม่ระหว่างใช้งาน
- ตรวจสอบเงื่อนไข game rule สำคัญ (เริ่มเกม, phase, โหวต, revive, dead-state)
- ตรวจสอบความเสถียรในการใช้งานจริงบน Windows
- ตรวจสอบเกณฑ์พร้อมปล่อย release (build/test/analyze ผ่าน)

---

## 2) ขอบเขตระบบที่ต้องทดสอบ

- การติดตั้งและเปิดระบบ (Server + Flutter)
- Authentication / Session / Auto-connect WS
- Social / Friends / Invite / Lobby
- Start Game และการ Broadcast เหตุการณ์
- Gameplay หลัก (กลางวัน/กลางคืน/ตาย/ชุบ/ชนะ)
- Chat และสิทธิ์ตามสถานะผู้เล่น
- เครือข่าย (Internet, DNS, HTTPS, WS reconnect)
- เสถียรภาพและการฟื้นตัวเมื่อระบบ/เน็ตผิดปกติ
- Static quality gate (`flutter analyze`, `cargo check`, `cargo test`)

---

## 3) สภาพแวดล้อมทดสอบ (Test Environment)

- OS: Windows 10.0.26200
- Shell: PowerShell
- Workspace: `D:/software_project/areyoughost`
- Frontend: Flutter Windows
- Backend: Rust (`areyoughost_server`)
- DB: PostgreSQL/Supabase ตาม `.env`

ข้อมูลทดสอบขั้นต่ำ:
- บัญชีผู้ใช้อย่างน้อย 2 บัญชี (`host`, `invitee`)
- ห้อง private 1 ห้อง
- ผู้เล่นในห้องอย่างน้อย 2 คนสำหรับทดสอบเริ่มเกม

---

## 4) ผลทดสอบที่รันจริงแล้วในรอบนี้ (Executed Evidence)

### NET-01: ตรวจการเข้าถึงอินเทอร์เน็ต (ICMP)

คำสั่ง:

```powershell
ping -n 20 8.8.8.8
```

ผลลัพธ์:
- สถานะ: PASS
- ส่ง 20 รับ 20 สูญหาย 0%
- RTT: Min 5ms / Avg 10ms / Max 47ms
- หมายเหตุ: มี latency spike ชั่วคราว แต่ไม่สูญหายแพ็กเก็ต

### NET-02: ตรวจ DNS Resolution

คำสั่ง:

```powershell
nslookup google.com
```

ผลลัพธ์:
- สถานะ: PASS
- resolve ได้ทั้ง IPv4/IPv6

### NET-03: ตรวจ HTTPS Outbound

คำสั่ง:

```powershell
curl.exe -I --max-time 10 https://www.google.com
```

ผลลัพธ์:
- สถานะ: PASS
- ได้ `HTTP/1.1 200 OK`

---

## 5) ตาราง Test Case ครอบคลุมทั้งระบบ (ละเอียด)

คำอธิบายสถานะ:
- `PASS` = ผ่านตามคาดหวัง
- `FAIL` = ไม่ผ่าน/พฤติกรรมผิด
- `BLOCK` = ทดสอบไม่ได้เพราะ dependency ไม่พร้อม
- `TODO` = ยังไม่ execute ในรอบนี้

### 5.1 หมวด ENV / Build / Run

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| ENV-01 | ตรวจเครื่องมือพื้นฐาน | `flutter --version`, `rustc --version`, `cargo --version` | คำสั่งทำงานครบ ไม่มี error | TODO |
| ENV-02 | โหลด dependency ฝั่ง Flutter | เข้า `frontend` แล้วรัน `flutter pub get` | dependency ครบ ไม่มี conflict | TODO |
| ENV-03 | คอมไพล์ backend | รัน `cargo check -p areyoughost_server` | compile ผ่าน | PASS |
| ENV-04 | เปิด server สำเร็จ | รัน `cargo run -p areyoughost_server` | server start และพร้อมรับ WS/API | TODO |
| ENV-05 | เปิด Flutter Windows สำเร็จ | รัน `flutter run -d windows` | แอปเปิดได้ ไม่ค้าง ไม่ crash | TODO |
| ENV-06 | ตรวจ static quality gate | `flutter analyze` + `cargo test -p areyoughost_server` | ผ่านตามเกณฑ์ CI | TODO |

### 5.2 หมวด Authentication / Session

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| AUTH-01 | Login สำเร็จ | ล็อกอินด้วยบัญชีถูกต้อง | เข้าแอปได้, token/session ถูกเก็บ | TODO |
| AUTH-02 | Login ผิดพลาด | ใส่รหัสผ่านผิด | แจ้ง error ชัดเจน, ไม่เข้าแอป | TODO |
| AUTH-03 | Auto restore session | ปิด/เปิดแอปใหม่หลังเคย login | session ถูก restore, ไม่หลุดหน้า login | TODO |
| AUTH-04 | WS auto-connect หลังมี session | เปิดแอปเมื่อมี token อยู่แล้ว | presence online ขึ้นเร็ว, ต่อ WS อัตโนมัติ | TODO |
| AUTH-05 | Logout | logout จากหน้า home | session/token ถูกล้าง, กลับหน้า login | TODO |

### 5.3 หมวด Social / Friend / Invite

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| SOC-01 | สร้างห้อง private | ผู้เล่น host สร้างห้อง | ได้ room code/room state ถูกต้อง | TODO |
| SOC-02 | ส่ง invite ถึงเพื่อนออนไลน์ | host ส่ง invite ให้ invitee | ฝั่งปลายทางได้รับ `invite.received` | PASS |
| SOC-03 | Badge จดหมายแดง | invitee มีคำเชิญใหม่ | ไอคอน mail แสดง badge | TODO |
| SOC-04 | ไม่มี invite | กด mail ตอนคำเชิญว่าง | แจ้ง "ไม่มีคำเชิญชวน" | TODO |
| SOC-05 | รับคำเชิญเข้าห้อง | invitee กด accept | เข้าห้องเดียวกับ host สำเร็จ | PASS |
| SOC-06 | ปฏิเสธคำเชิญ | invitee กด reject | คำเชิญถูกปิด, ไม่เข้าห้อง | TODO |
| SOC-07 | UI invitee เหมือน host (ยกเว้น host control) | invitee เข้าหน้าห้อง | เห็น layout ห้องเหมือนกัน แต่ซ่อนปุ่มเริ่มเกม/รหัสเชิญ | TODO |
| SOC-08 | จำนวนผู้เล่นในห้องถูกต้อง | host + invitee อยู่ห้องเดียวกัน | รายชื่อผู้เล่นตรงกันทั้งสองฝั่ง | PASS |

### 5.4 หมวด Start Game / Room State

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| GAME-START-01 | ห้ามเริ่มเกมเมื่อผู้เล่นไม่พอ | เหลือผู้เล่น < 2 แล้วกดเริ่มเกม | ระบบปฏิเสธและแจ้งเหตุผล | TODO |
| GAME-START-02 | เริ่มเกมเมื่อผู้เล่นครบ | มีผู้เล่น >= 2 แล้วกดเริ่มเกม | room เปลี่ยนเป็น playing | TODO |
| GAME-START-03 | Broadcast เริ่มเกม | หลัง host กดเริ่ม | ทุกคนได้รับ `game.started` พร้อมกัน | TODO |

### 5.5 หมวด Gameplay Rule (Server Authoritative)

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| RULE-01 | phase เริ่มต้นเป็น Night | เริ่มเกมใหม่ | เกมเข้า Night phase ทันที | PASS |
| RULE-02 | ปฏิเสธ night action ตอน Day | ยิง action กลางวัน | server ตอบ reject ตามกติกา | PASS |
| RULE-03 | โหวตกลางวันครบเงื่อนไข | ผู้เล่นโหวตครบ | execute/จบวันตามกติกา | PASS |
| RULE-04 | ผู้เล่นตายห้ามโหวต | ทำให้ผู้เล่นตายแล้วลองโหวต | โหวตไม่สำเร็จ | PASS |
| RULE-05 | ผู้เล่นตายห้ามใช้สกิล | ผู้เล่นตายกดสกิลกลางคืน | ระบบปฏิเสธ | PASS |
| RULE-06 | ผู้เล่นตายห้ามแชทกลางวัน | ผู้เล่นตายพิมพ์แชท | ส่งไม่ออก/ถูกปฏิเสธ | PASS |
| RULE-07 | Revive ยกเลิกผลตายในคืนเดียวกัน | ผีฆ่า + หมอผีชุบเหยื่อคืนเดียวกัน | เหยื่อกลับ alive | PASS |
| RULE-08 | Global chat จำกัดตาม phase | ลองแชทนอก phase ที่อนุญาต | ระบบ reject | TODO |
| RULE-09 | ตรวจ win condition ฝั่งผี | เดินเกมจนเข้าขชนะฝั่งผี | `winnerKind` ถูกต้อง | TODO |
| RULE-10 | Deck ไม่ซ้ำบทพิเศษผิดกติกา | สุ่มบทหลายรอบ | ไม่เกิดบทพิเศษซ้ำเกินข้อกำหนด, บทไม่พอเติมชาวบ้าน | PASS |

### 5.6 หมวด UI/UX In-game

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| UI-01 | Grid ผู้เล่นขนาดสม่ำเสมอ | เข้า day/night grid | การ์ดผู้เล่นทุกช่องกว้างเท่ากัน | TODO |
| UI-02 | สถานะตายสะท้อนถูกต้อง | ผู้เล่นถูกฆ่า | UI เปลี่ยนเป็นสถานะตายทันที | TODO |
| UI-03 | สถานะชุบกลับมา alive | ทำ revive สำเร็จ | UI กลับเป็นผู้เล่นปกติ | TODO |
| UI-04 | ปุ่มที่ไม่ควรกดต้อง disabled | ผู้เล่นตายหรือไม่ถึง phase | ปุ่ม action ถูก disable/แจ้งเตือนชัดเจน | TODO |

### 5.7 หมวด Network / Disconnect / Reconnect (สำคัญ)

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| NET-04 | หลุดเน็ตตอนอยู่ lobby | ปิดเน็ต 15-30 วินาทีแล้วเปิดใหม่ | UI แสดง disconnected และ recover ได้ | TODO |
| NET-05 | หลุดเน็ตระหว่างกด action | กด action แล้วตัดเน็ตทันที | ไม่ค้าง, มี error handling, retry/reconnect ตามดีไซน์ | TODO |
| NET-06 | หลุดนานเกิน timeout | ตัดเน็ต 60-120 วินาที | ระบบ timeout ชัดเจนและมีทางกลับเข้าเกม/ห้อง | TODO |
| NET-07 | เน็ตกระพริบหลายรอบ | ปิด/เปิดเน็ต 3-5 รอบ | แอปไม่ crash, state ไม่เพี้ยน, ไม่ยิงซ้ำ | TODO |
| NET-08 | DNS ผิดพลาดชั่วคราว | ตั้ง DNS ผิด แล้วลอง connect จากนั้นแก้กลับ | แจ้งข้อผิดพลาดชัด, recover หลัง DNS ปกติ | TODO |
| NET-09 | server restart ระหว่างใช้งาน | รีสตาร์ท backend ขณะ client ออนไลน์ | client ตรวจจับการหลุดและกลับมาเชื่อมต่อได้ | TODO |
| NET-10 | duplicate event หลัง reconnect | หลุดแล้วต่อใหม่ใน phase เดียวกัน | ไม่เกิดข้อความ/action ซ้ำ | TODO |

### 5.8 หมวด Stability / Reliability

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| STB-01 | เปิด/ปิดแอปซ้ำ | เปิดและปิดแอป 20 รอบ | ไม่ crash, memory โตไม่ผิดปกติ | TODO |
| STB-02 | เล่นต่อเนื่องระยะยาว | เล่น 1-2 ชั่วโมง | ไม่ freeze, response time คงที่ | TODO |
| STB-03 | Server ไม่ panic ใน test suite | รัน `cargo test -p areyoughost_server` | ไม่เกิด panic ในเคสหลัก | PASS |
| STB-04 | Asset pipeline ปกติ | รัน flutter test/check asset | โหลด asset ได้ครบ, ไม่มี missing manifest | PASS |
| STB-05 | เคส build lock บน Windows | จำลอง/เจอ C1041 แล้วทำ recovery flow | recovery สำเร็จตาม runbook | TODO |

### 5.9 หมวด Security / Data Safety (พื้นฐาน release)

| ID | รายการทดสอบ | ขั้นตอนทดสอบ | ผลที่คาดหวัง | สถานะ |
|----|--------------|---------------|---------------|--------|
| SEC-01 | ไม่เปิดเผย secret ใน log | ทำ login/invite/gameplay แล้วตรวจ log | ไม่มี token/password/secret หลุด | TODO |
| SEC-02 | ป้องกัน action โดยสิทธิ์ไม่ถูกต้อง | ผู้เล่นทั่วไปพยายามทำ host action | server ปฏิเสธ | TODO |
| SEC-03 | จัดการ input ผิดรูปแบบ | ส่ง payload ผิด schema | ระบบตอบ error โดยไม่ล่ม | TODO |
| SEC-04 | session invalid/expired | ใช้ token หมดอายุ | ถูกบังคับ re-auth อย่างถูกต้อง | TODO |

---

## 6) ชุดคำสั่งมาตรฐานสำหรับรันทดสอบก่อนปล่อย

```powershell
cd D:\software_project\areyoughost
cargo check -p areyoughost_server
cargo test -p areyoughost_server
```

```powershell
cd D:\software_project\areyoughost\frontend
flutter test test/qa_checklist_test.dart
flutter analyze
flutter run -d windows
```

---

## 7) เกณฑ์ผ่านระบบ (Release Acceptance Criteria)

- หมวด `ENV`, `AUTH`, `SOC`, `GAME-START`, `RULE`, `NET` ผ่านอย่างน้อย 100% สำหรับเคส Critical
- กรณีเน็ตหลุด (NET-04 ถึง NET-10) ต้องไม่ทำให้แอป crash หรือข้อมูลสถานะเสีย
- ฝั่ง server test (`cargo test`) และ static checks ต้องผ่านทั้งหมด
- ไม่พบ bug ระดับ blocker/critical ใน regression รอบสุดท้าย

---

## 8) สรุปสถานะรอบปัจจุบัน

ผลที่ยืนยันแล้ว:
- PASS: `NET-01`, `NET-02`, `NET-03`, `ENV-03`, `SOC-02`, `SOC-05`, `SOC-08`, `RULE-01`, `RULE-02`, `RULE-03`, `RULE-04`, `RULE-05`, `RULE-06`, `RULE-07`, `RULE-10`, `STB-03`, `STB-04`
- TODO: `ENV-06` (ยังไม่ได้ปิดประเด็น `flutter analyze`)

ผลที่ยังต้อง execute เพิ่ม:
- หมวด Functional และ Reconnect ในแอปจริง (AUTH/SOC/GAME/RULE/NET เพิ่มเติม/STB/SEC)
- `RULE-09` ยังต้องยืนยันเชิงพฤติกรรม end-to-end บนเกมจริง

ข้อสรุป:
- เครือข่ายเครื่องทดสอบพร้อมใช้งานปกติ (ICMP, DNS, HTTPS ผ่าน)
- ยังต้องรัน test case เชิงระบบในแอปตามตารางทั้งหมดเพื่อ sign-off release

---

## 9) แบบฟอร์มบันทึกผล (สำหรับผู้ทดสอบ)

- Release candidate:
- วันที่/เวลาเริ่มทดสอบ:
- วันที่/เวลาจบทดสอบ:
- ผู้ทดสอบ:
- จำนวนเคสทั้งหมด:
- ผ่าน:
- ไม่ผ่าน:
- BLOCK:
- หมายเหตุปัญหาสำคัญ:
- ผลการอนุมัติปล่อย (GO/NO-GO):
