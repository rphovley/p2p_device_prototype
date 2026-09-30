import type { APIGatewayProxyStructuredResultV2, LambdaFunctionURLEvent } from "aws-lambda";

interface NotifyRequest {
  ticket: string;
  /** Base64 AES-GCM envelope (nonce/ciphertext/tag) encrypted with the pairing key. */
  encryptedPayload: string;
}

export async function handler(
  event: LambdaFunctionURLEvent
): Promise<APIGatewayProxyStructuredResultV2> {
  const request = JSON.parse(event.body ?? "{}") as Partial<NotifyRequest>;

  if (!request.ticket || !request.encryptedPayload) {
    return { statusCode: 400, body: JSON.stringify({ error: "missing ticket or encryptedPayload" }) };
  }

  // TODO:
  // 1. Look up { platform, pushToken, expiresAt } from the Tickets table by request.ticket.
  // 2. Reject if not found or expired (404/410) so the PC knows to ask the phone to re-register.
  // 3. Rate-limit per ticket.
  // 4. Forward encryptedPayload as the notification's data payload to APNs (platform === "ios")
  //    or FCM (platform === "android"); the phone app decrypts locally with the pairing key,
  //    so this function and Apple/Google only ever see ciphertext.

  return { statusCode: 202, body: JSON.stringify({ status: "queued" }) };
}
