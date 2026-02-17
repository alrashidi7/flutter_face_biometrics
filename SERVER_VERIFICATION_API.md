# Server Verification API

Complete flow for biometric auth: registration → challenge verification → recovery (new device).

---

## 1. Registration Flow

When the user registers, the app:

1. Captures selfie with liveness (exactly one face, blink detection)
2. Converts selfie to embedding (FaceNet 128D)
3. Signs embedding with device biometric key
4. POSTs to registration endpoint

**POST** `/biometric/register` (or your registration endpoint) with JSON:

```json
{
  "embedding": [0.1, -0.2, ...],
  "biometricSignature": "base64...",
  "biometricPublicKey": "base64 or PEM...",
  "signedPayload": "base64...",
  "deviceSignature": "sha256..."
}
```

`deviceSignature` is from [DeviceIntegrityReport] — hardware-bound identifier. Store with user for device attestation.

Include auth headers (e.g. `Authorization: Bearer <token>`).

**Server logic:**
1. Verify signature over `signedPayload` using `biometricPublicKey`
2. Verify embedding (e.g. ensure valid, no duplicate)
3. Store for user: `embedding` + `biometricPublicKey`
4. Return `{"code": "success"}`

---

## 2. Action Verification (Challenge Flow)

When the user tries to perform a sensitive action (or on app open):

1. Server sends a challenge (e.g. random nonce)
2. App calls `BiometricExportService.verifyWithChallenge(apiUrl, challenge)`
3. User authenticates with biometric, app signs challenge, POSTs to verify endpoint

**POST** `/biometric/verify-challenge` with JSON:

```json
{
  "biometricSignature": "base64...",
  "biometricPublicKey": "base64 or PEM...",
  "signedPayload": "<challenge string>",
  "deviceSignature": "sha256..."
}
```

**Server logic:**
1. Verify `biometricSignature` over `signedPayload` (the challenge) using `biometricPublicKey`
2. Check `biometricPublicKey` is one of the user's enrolled keys
3. If valid → return `{"code": "success"}`, allow action
4. If public key not found → return `{"code": "signature_invalid"}` → app triggers recovery

---

## 3. Recovery Flow (New Device)

When challenge verification returns `signature_invalid` (user changed phone):

1. App prompts user to take selfie + liveness
2. Builds `BiometricExportData` (embedding + signature + publicKey + signedPayload)
3. POSTs to **recovery** endpoint

**POST** `/biometric/recover` (or `/biometric/enroll-device`) with same payload as registration:

```json
{
  "embedding": [0.1, -0.2, ...],
  "biometricSignature": "base64...",
  "biometricPublicKey": "base64 or PEM...",
  "signedPayload": "base64...",
  "deviceSignature": "sha256..."
}
```

**Server logic:**
1. Verify embedding matches user's stored embedding (cosine similarity ≥ threshold)
2. Verify signature over `signedPayload` using `biometricPublicKey`
3. Add new `biometricPublicKey` to user's enrolled devices
4. Return `{"code": "success"}`
5. Next time app sends challenge, this device will be recognized

---

## Response Codes

| Code | Meaning |
|------|---------|
| `success` / `verified` | Verification passed. |
| `signature_invalid` | Signature not valid or device not enrolled. Trigger recovery. |
| `embedding_mismatch` | Face does not match user. Reject. |

---

## Client Usage (Flutter)

```dart
// Registration
final data = await exportService.buildExportDataFromFile(capturedImage);
final result = await exportService.verifyAndUploadBiometricData(registerUrl, data);

// Action verification (challenge)
final challenge = await getChallengeFromServer(); // your API
final result = await exportService.verifyWithChallenge(verifyUrl, challenge);
if (result is BiometricVerificationSignatureInvalid) {
  // Trigger recovery: capture selfie, then enroll new device
  final recoveryData = await exportService.buildExportDataFromFile(newSelfie);
  await exportService.verifyAndUploadBiometricData(recoverUrl, recoveryData);
}
```

## App Flow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│ REGISTRATION                                                     │
│ Selfie + liveness → embedding → sign(embedding) → POST /register │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ ACTION / APP OPEN                                                │
│ Server sends challenge → sign(challenge) → POST /verify-challenge│
│                                                                  │
│ If success → allow action                                        │
│ If signature_invalid → RECOVERY                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ RECOVERY (new device)                                            │
│ Selfie + liveness → embedding → sign(embedding) → POST /recover  │
│ Server: verify embedding matches user → add new public key       │
│ Next challenge will succeed with this device                     │
└─────────────────────────────────────────────────────────────────┘
```
