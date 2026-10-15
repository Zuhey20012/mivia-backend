import { Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { dac7Csv, dac7Report, parseYear } from "./dac7";
import { currentMonth, storeStatement } from "./statements";

export async function adminDac7(req: Request, res: Response) {
  try {
    res.json({ ok: true, ...(await dac7Report(parseYear(req.query.year))) });
  } catch (e) { sendError(res, e); }
}

export async function adminDac7Csv(req: Request, res: Response) {
  try {
    const year = parseYear(req.query.year);
    const csv = await dac7Csv(year);
    res.set("Cache-Control", "private, no-store");
    res.set("Content-Disposition", `attachment; filename="malvoya-dac7-${year}.csv"`);
    res.type("text/csv; charset=utf-8").send(`﻿${csv}`); // BOM: spreadsheet programs then read UTF-8 names right
  } catch (e) { sendError(res, e); }
}

export async function adminStoreStatement(req: Request, res: Response) {
  try {
    const id = positiveId(req.params.id);
    if (!id || !(await prisma.store.findUnique({ where: { id }, select: { id: true } }))) throw new ApiError("Store not found", 404);
    const month = typeof req.query.month === "string" && req.query.month ? req.query.month : currentMonth();
    res.json({ ok: true, ...(await storeStatement(id, month)) });
  } catch (e) { sendError(res, e); }
}
