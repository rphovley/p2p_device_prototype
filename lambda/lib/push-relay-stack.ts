import * as cdk from "aws-cdk-lib";
import * as lambda from "aws-cdk-lib/aws-lambda-nodejs";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import { Construct } from "constructs";

/**
 * Minimal push relay: two functions behind their own Function URLs (no API
 * Gateway needed for an example this small).
 *
 * - register: phone posts its push token, gets back a sealed ticket
 *   (opaque to everyone but this stack) that it hands to the PC over BLE.
 * - notify: PC posts { ticket, encryptedPayload }, this looks up the token
 *   behind the ticket and forwards to APNs/FCM.
 *
 * Rate limiting, ticket expiry/refresh, and the actual APNs/FCM calls are
 * left as TODOs in the handlers — this stack just wires the plumbing.
 */
export class PushRelayStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const tickets = new dynamodb.TableV2(this, "Tickets", {
      partitionKey: { name: "ticketId", type: dynamodb.AttributeType.STRING },
      timeToLiveAttribute: "expiresAt",
      billing: dynamodb.Billing.onDemand(),
    });

    const registerFn = new lambda.NodejsFunction(this, "RegisterFn", {
      entry: "src/register.ts",
      handler: "handler",
      environment: {
        TICKETS_TABLE_NAME: tickets.tableName,
      },
    });
    tickets.grantWriteData(registerFn);

    const notifyFn = new lambda.NodejsFunction(this, "NotifyFn", {
      entry: "src/notify.ts",
      handler: "handler",
      environment: {
        TICKETS_TABLE_NAME: tickets.tableName,
      },
    });
    tickets.grantReadData(notifyFn);

    const registerUrl = registerFn.addFunctionUrl({
      authType: cdk.aws_lambda.FunctionUrlAuthType.NONE,
    });
    const notifyUrl = notifyFn.addFunctionUrl({
      authType: cdk.aws_lambda.FunctionUrlAuthType.NONE,
    });

    new cdk.CfnOutput(this, "RegisterUrl", { value: registerUrl.url });
    new cdk.CfnOutput(this, "NotifyUrl", { value: notifyUrl.url });
  }
}
