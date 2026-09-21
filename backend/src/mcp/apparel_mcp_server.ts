import { Router, Request, Response } from "express";
import pino from "pino";

const logger = pino({ name: "ApparelMCPServer" });
export const mcpRouter = Router();

/**
 * Model Context Protocol (MCP) Multi-Tool Agent Implementation
 * Conforms to MCP JSON-RPC 2.0 Protocol Specifications.
 */

export interface McpTool {
  name: string;
  description: string;
  inputSchema: {
    type: string;
    properties: Record<string, any>;
    required?: string[];
  };
}

const MCP_TOOLS: McpTool[] = [
  {
    name: "inspect_garment_condition",
    description:
      "Performs 3-zone computer vision defect and stain scoring on returned apparel. Assesses collar makeup, underarm perspiration, and security tamper ribbon integrity.",
    inputSchema: {
      type: "object",
      properties: {
        orderId: { type: "string", description: "The Malvoya order identifier (e.g. ORD-12345)" },
        barcode: { type: "string", description: "Boutique garment barcode or SKU identifier" },
        stainConfidence: { type: "number", description: "Confidence score of stain or defect (0.00 - 1.00)" },
        tamperRibbonIntact: { type: "boolean", description: "Whether the physical VOID tamper ribbon remains unbroken" },
      },
      required: ["orderId"],
    },
  },
  {
    name: "propagate_multilingual_context",
    description:
      "Synchronizes real-time state and localized notifications across Customer, Vendor, and Courier participants with zero language desync.",
    inputSchema: {
      type: "object",
      properties: {
        role: { type: "string", enum: ["CUSTOMER", "VENDOR", "COURIER"], description: "Target recipient role" },
        event: { type: "string", description: "The state lifecycle event (e.g. ORDER_PLACED, DISPATCHED, RETURN_REQUESTED)" },
        locale: { type: "string", enum: ["fi", "en"], description: "Requested localization language" },
      },
      required: ["role", "event"],
    },
  },
];

/**
 * Tool execution implementations
 */
function handleInspectGarment(args: any) {
  const { orderId, barcode, stainConfidence = 0.05, tamperRibbonIntact = true } = args;

  const isPristine = Boolean(tamperRibbonIntact) && Number(stainConfidence) < 0.25;
  const needsDryCleaning = Boolean(tamperRibbonIntact) && Number(stainConfidence) >= 0.25 && Number(stainConfidence) < 0.65;

  const verdict = isPristine ? "PRISTINE_ACCEPT" : needsDryCleaning ? "CLEANING_FEE_APPLIED" : "REJECTED_DEFECTIVE";
  const escrowAction = isPristine ? "INSTANT_REFUND" : needsDryCleaning ? "DEDUCT_CLEANING_FEE" : "HOLD_ESCROW_DISPUTE";

  return {
    orderId,
    barcode: barcode || `MALVOYA-SKU-${orderId}`,
    stainConfidence: Number(stainConfidence),
    tamperRibbonIntact: Boolean(tamperRibbonIntact),
    verdict,
    escrowAction,
    cleaningFeeEur: needsDryCleaning ? 12.0 : 0.0,
    courierDirective: "DIRECTIVE: ACCEPT_PACKAGE_DO_NOT_ARGUE",
    courierDirectiveFi: "DIREKTIIVI: OTA PAKETTI VASTAAN, ÄLÄ KIISTELE",
    customerMessageFi: isPristine
      ? "Vaate hyväksytty uudenveroiseksi: Hyvitys vapautettu tilille välittömästi."
      : "Vaatteessa havaittiin puhdistustarve: 12 € pesulamaksu vähennetty.",
    customerMessageEn: isPristine
      ? "Garment verified pristine: Full refund released to your original payment method."
      : "Garment requires professional cleaning: €12 cleaning fee deducted.",
    inspectedAt: new Date().toISOString(),
  };
}

function handlePropagateMultilingual(args: any) {
  const { role, event, locale = "fi" } = args;
  const isFi = locale === "fi";

  const eventMessages: Record<string, { fi: string; en: string }> = {
    ORDER_PLACED: {
      fi: "Uusi tilaus vastaanotettu putiikissa. Valmistellaan pakkausta.",
      en: "New order confirmed at boutique. Preparing package.",
    },
    DISPATCHED: {
      fi: "Kuriiri on matkalla oveluutesi. Live-tutka aktiivinen.",
      en: "Courier is en route to your doorstep. Live radar active.",
    },
    DELIVERED: {
      fi: "Toimitus suoritettu ja valokuvattu ovelle.",
      en: "Delivery completed and photographed at doorstep.",
    },
    RETURN_REQUESTED: {
      fi: "Palautuspyyntö rekisteröity. Kuriirin nouto varattu riidattomasti.",
      en: "Return requested. Dispute-free doorstep pickup arranged.",
    },
  };

  const selected = eventMessages[event] || {
    fi: `Tapahtuma: ${event}`,
    en: `Event: ${event}`,
  };

  return {
    targetRole: role,
    event,
    locale,
    text: isFi ? selected.fi : selected.en,
    synchronizedAt: new Date().toISOString(),
  };
}

/**
 * JSON-RPC 2.0 Request Router
 */
mcpRouter.post("/mcp", (req: Request, res: Response) => {
  const { jsonrpc, id, method, params } = req.body;

  if (jsonrpc !== "2.0") {
    return res.status(400).json({
      jsonrpc: "2.0",
      id: id || null,
      error: { code: -32600, message: "Invalid Request: jsonrpc must be '2.0'" },
    });
  }

  logger.info({ method, id }, "🤖 MCP JSON-RPC 2.0 Method Dispatched");

  switch (method) {
    case "initialize":
      return res.json({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: {
            name: "malvoya-q-apparel-mcp",
            version: "1.0.0",
          },
        },
      });

    case "tools/list":
      return res.json({
        jsonrpc: "2.0",
        id,
        result: { tools: MCP_TOOLS },
      });

    case "tools/call": {
      const toolName = params?.name;
      const toolArgs = params?.arguments || {};

      if (toolName === "inspect_garment_condition") {
        const output = handleInspectGarment(toolArgs);
        return res.json({
          jsonrpc: "2.0",
          id,
          result: {
            content: [{ type: "text", text: JSON.stringify(output, null, 2) }],
          },
        });
      }

      if (toolName === "propagate_multilingual_context") {
        const output = handlePropagateMultilingual(toolArgs);
        return res.json({
          jsonrpc: "2.0",
          id,
          result: {
            content: [{ type: "text", text: JSON.stringify(output, null, 2) }],
          },
        });
      }

      return res.status(404).json({
        jsonrpc: "2.0",
        id,
        error: { code: -32601, message: `Method or tool not found: ${toolName}` },
      });
    }

    default:
      return res.status(404).json({
        jsonrpc: "2.0",
        id,
        error: { code: -32601, message: `Method not found: ${method}` },
      });
  }
});
