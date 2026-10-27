# Two-device offline demo (Slice 1)

REAL DEVICE ACCEPTANCE PENDING until these steps pass on two physical Androids.

1. Install the debug APK on both phones.
2. Enable Airplane mode (SIM mobile data and internet off).
3. Turn Bluetooth on. Turn Wi-Fi on if the phone requires it for Nearby (do not join a network).
4. Open the app.
5. Tap Continue nearby without account (OTP is not required), or Auth -> Use offline nearby without OTP.
6. Grant Nearby / Bluetooth / location permissions if asked. Denial must not crash other tabs.
7. Open the Nearby tab. Discovery starts.
8. Select the peer on one phone and tap Connect.
9. Accept the incoming request on the other phone. Reject cancels pairing.
10. Compare the 6-digit safety code on both screens. Do not confirm if they differ.
11. Both users tap Accept to confirm.
12. Type Hello and send.
13. Sender status should move Queued -> Sending -> Waiting for ACK -> Delivered. Receiver shows the text once.
14. Force-stop the receiver app, send another message on the sender (Queued / Failed).
15. Reopen the receiver, grant reconnect/accept if asked, confirm the pending message delivers automatically.
16. Force-stop and reopen the sender. History and Delivered/Queued status remain.

QR pairing is not in this slice. Device reboot background retry is not in this slice.
