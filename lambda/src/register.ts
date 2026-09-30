import type { APIGatewayProxyStructuredResultV2, LambdaFunctionURLEvent } from "aws-lambda";
import { randomUUID } from "node:crypto";

interface RegisterRequest {
  platform: "ios" | "android";
  pushToken: string;
}

interface RegisterResponse {
  ticket: string;
  expiresAt: string;
}

const TICKET_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days; PC/phone should refresh before this.

export async function handler(
  event: LambdaFunctionURLEvent
): Promise<APIGatewayProxyStructuredResultV2> {
  const request = JSON.parse(event.body ?? "{}") as Partial<RegisterRequest>;

  if (!request.platform || !request.pushToken) {
    return { statusCode: 400, body: JSON.stringify({ error: "missing platform or pushToken" }) };
  }

  // TODO: write { ticketId, platform, pushToken, expiresAt } to the Tickets
  // table (TICKETS_TABLE_NAME env var). ticketId below is a placeholder for
  // the real opaque, unguessable ticket ID that gets stored server-side.
  const ticketId = randomUUID();
  const expiresAt = new Date(Date.now() + TICKET_TTL_MS);

  const response: RegisterResponse = {
    ticket: ticketId,
    expiresAt: expiresAt.toISOString(),
  };

  return { statusCode: 200, body: JSON.stringify(response) };
}
