# Jhadimadi.com — IT / Web / App Security & Architecture Audit

Audit date: 2026-09-23
Scope: Uploaded source ZIP, React/Vite frontend, Express backend, Supabase migrations, local JSON data, authentication, API routes, storage, AI endpoints and configuration.

## গুরুত্বপূর্ণ সীমাবদ্ধতা
এই অডিটটি source-code/static audit + parser checks। Dependency installation/network timeout হওয়ায় full `npm run build` এবং browser/E2E test সম্পন্ন করা যায়নি। তাই নিচের তালিকাটি source-এ শনাক্ত সমস্যার তালিকা; production runtime-এর প্রতিটি feature 100% tested বলে ধরা যাবে না।

## Critical findings

### C-01 — Repository-তে admin signing secret ও credentials ছিল
- `data/.admin_secret`-এ persistent admin signing secret ছিল।
- `data/admin_credentials.json`-এ admin email/phone, password hash ও session metadata ছিল।
- Fix: এগুলো fixed package থেকে সরানো হয়েছে; production `ADMIN_SECRET_KEY` environment variable বাধ্যতামূলক করা হয়েছে; seed script-এ default password বন্ধ করা হয়েছে।

### C-02 — Emergency admin seed-এ hard-coded fallback credential
- Emergency endpoint-এ default emergency key এবং default admin password ছিল।
- Fix: `ADMIN_EMERGENCY_KEY` এখন অবশ্যই environment variable; key না থাকলে emergency seed ব্যর্থ হবে; password কমপক্ষে 12 অক্ষর; hard-coded identity/password সরানো হয়েছে।

### C-03 — Password reset flow takeover-risk
- Recovery endpoint reset token ও verification code response-এ ফেরত দিত।
- Phone match একাই reset verification হিসেবে কাজ করতে পারত।
- Fix: reset token/code আর response-এ ফেরত দেওয়া হয় না; configured private recovery webhook-এর মাধ্যমে পাঠাতে হয়; reset-এর জন্য token + code দুটোই বাধ্যতামূলক; route rate-limited।

### C-04 — CORS origin reflection + credentials
- Arbitrary `Origin` reflect করে credentials allow করা হচ্ছিল।
- Fix: explicit `CORS_ORIGINS`/`APP_URL` allowlist; unknown origin reject; `Vary: Origin` যোগ করা হয়েছে।

### C-05 — Supabase RLS/GRANT configuration অত্যন্ত permissive
Migration history-তে একাধিক জায়গায় `GRANT ALL ... TO anon, authenticated` এবং public `USING (true) WITH CHECK (true)` policies দেখা গেছে। এটি production data-এর ক্ষেত্রে privilege escalation/data modification risk তৈরি করতে পারে।
- Fix package-এ source-level hardening করা হয়েছে, কিন্তু database-এ migration apply না করলে এটি সম্পূর্ণ সমাধান হবে না।
- Production deployment-এর আগে Supabase SQL Editor-এ final RLS review/verification বাধ্যতামূলক।

### C-06 — NID AI endpoint public এবং sensitive data processing করে
`/api/nid-verify-gemini` authentication ছাড়া NID image নেয়, OCR/identity fields বের করে এবং private storage-এ document রাখে।
- Fix: strict IP rate limit + image MIME/size validation যোগ হয়েছে।
- Remaining architectural requirement: NID processing production-এ authenticated/consented flow-এর মধ্যে রাখতে হবে এবং retention/deletion policy প্রয়োগ করতে হবে।
- AI result-কে সরকারি identity verification হিসেবে ব্যবহার করা যাবে না।

## High findings

### H-01 — Job candidate data exposure
`/api/jobs/candidates` public GET-এ candidate records পড়া যেত।
### H-02 — Job application privacy/authorization gap
`/api/jobseeker/applications` query দিয়ে application data পাওয়া যায়; status update endpoint-এ authorization ছিল না।
### H-03 — Public job creation/deletion
`/api/jobs` POST এবং DELETE admin authorization ছাড়া ছিল।
### H-04 — Public post deletion
`/api/posts/:id` DELETE authorization ছাড়া ছিল।
### H-05 — Blood donor delete authorization gap
Blood donor DELETE route-এ admin authorization ছিল না।
### H-06 — Blood donor password handling
Blood donor record-এ password field server/database payload-এ রাখা হচ্ছে এবং registration response-এ donor record ফেরত দেওয়া হচ্ছে। Password authentication হলে dedicated hash/verification flow দরকার।
### H-07 — Order business-logic trust issue
Order creation client-supplied total, payment status, order status, product fields গ্রহণ করে। Status update routes-ও authorization ছাড়া ছিল। এটি price/payment manipulation-এর ঝুঁকি তৈরি করে।
### H-08 — Admin authentication brute-force surface
Global rate limit 360 req/min ছিল; admin auth-এর জন্য আলাদা failed-attempt lock থাকলেও route-specific protection দুর্বল ছিল।
- Fix: admin login/recovery/expensive AI routes-এ strict per-IP rate limiting যোগ হয়েছে।

## Medium findings

### M-01 — Local JSON + in-memory state as production persistence
Users/orders/admin sessions এবং বিভিন্ন runtime data local JSON/in-memory store-এ রাখা হয়েছে। Multi-instance deployment, restart, concurrent writes ও horizontal scaling-এ consistency সমস্যা হবে।

### M-02 — Duplicate Supabase clients/configuration
একাধিক Supabase client/config ছিল এবং একই project/key বিভিন্ন file-এ hard-code করা ছিল।
- Fix: client configuration environment-driven ও centralized করা হয়েছে।

### M-03 — Global runtime error suppression
`index.html` runtime `fetch`, WebSocket, failed-fetch এবং unhandled rejection error suppress করছিল।
- Fix: global suppression সরানো হয়েছে; প্রকৃত runtime error এখন observable থাকবে।

### M-04 — Global 15 MB JSON parser
সব API route-এর জন্য বড় body limit রাখা ছিল। Expensive AI routes-এ abuse risk বাড়ে।
- Fix: NID image 8 MB এবং voice audio 5 MB hard limit; MIME validation যোগ হয়েছে।

### M-05 — Hard-coded public contact data
Server/source-এ official phone/email fallback ছিল।
- Fix: `PUBLIC_OFFICIAL_PHONE` এবং `PUBLIC_OFFICIAL_EMAIL` environment configuration-এ সরানো হয়েছে।

### M-06 — Demo/runtime data package-এ personal phone/email
Uploaded ZIP-এর data files-এ বাস্তব-সদৃশ phone/email data ছিল।
- Fix: fixed ZIP-এ local data-এর phone/email synthetic demo values দিয়ে redacted করা হয়েছে।
- Production data Supabase/database-এ রাখা উচিত; source ZIP-এ নয়।

## Quality / maintainability findings

### Q-01 — API routes-এর authorization policy একীভূত নয়
কিছু route `requireAdminAuth`, কিছু `authenticateEmployer`, কিছু public, আবার কিছু sensitive route custom checks ব্যবহার করে। Central authorization policy প্রয়োজন।

### Q-02 — API error contract inconsistent
কিছু endpoint `error: err.message` client-এ ফেরত দেয়। Production-এ internal exception details প্রকাশ না করাই নিরাপদ।

### Q-03 — Order IDs / candidate codes use `Math.random()`
Security token-এর জন্য ব্যবহার না করা হলেও business identifiers-এ collision risk আছে। UUID/crypto.randomInt ব্যবহার করা উচিত।

### Q-04 — SQL migrations-এর বহু corrective/public-permission migration
Migration history-তে একই table-এর permission বারবার বদলানো হয়েছে। Final canonical schema + final RLS policy set রাখা maintainability ও security review সহজ করবে।

## Applied fixes in this package

1. Production admin signing secret must come from environment.
2. Removed persistent admin secret/credential files from package.
3. Removed hard-coded admin emergency key/password.
4. Secure recovery flow: no reset token/code in HTTP response.
5. Strict CORS allowlist.
6. Route-specific rate limiting for admin auth, recovery, NID, voice and order-AI endpoints.
7. NID/voice payload size and MIME validation.
8. Centralized environment-driven Supabase client configuration.
9. Removed global runtime error suppression.
10. Removed hard-coded official contact fallbacks from server.
11. Redacted local demo phone/email data.
12. Added `npm run security:audit`.
13. Employer API now requires verified Supabase Auth/admin access instead of trusting arbitrary employer IDs.
14. Protected job creation/deletion, post deletion, blood-donor deletion and order status mutation routes.
15. Production order creation recalculates product totals from the server-side product catalog when available.
16. Order notification responses no longer claim email was sent unless a configured webhook accepted the notification.
17. Added production security environment template.

## Verification performed

- JavaScript/TypeScript parser diagnostics: no syntax diagnostics in modified key files.
- Security audit script: PASS.
- Full TypeScript build: NOT VERIFIED because dependency installation timed out in the audit environment. Existing dependency/type errors were therefore not treated as proof that the application builds cleanly.

## Production deployment checklist

- Set `ADMIN_SECRET_KEY` to a new random secret of at least 32 characters.
- Set `ADMIN_EMERGENCY_KEY` only if emergency recovery is genuinely required.
- Set `ADMIN_RESET_DELIVERY_WEBHOOK` to a private authenticated recovery service.
- Set `CORS_ORIGINS` to the exact production origin(s).
- Set `PUBLIC_OFFICIAL_PHONE` and `PUBLIC_OFFICIAL_EMAIL`.
- Configure Supabase service-role credentials only on the server.
- Review/apply final RLS policies and remove `anon`/`authenticated` blanket grants.
- Rotate any credentials that were previously present in the original ZIP.
- Do not restore `data/admin_credentials.json` or `.admin_secret` into source control.
- Run `npm ci`, `npm run lint`, `npm run build`, then browser/API security tests in CI/CD.

