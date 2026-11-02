import { Router } from "express";
import { listProducts, searchProducts, getProduct, createProduct, updateProduct, deleteProduct } from "./products.controller";
import { auth, optionalAuth, requireRole } from "../../middleware/auth";
import { productVideoRoutes } from "./productVideos";
import { requireAgreement } from "../legal/agreements";

// Publishing (a visible new product, or making one visible) needs the Seller Terms in force to be accepted; drafts do not
const publishing = requireAgreement((req) => (req.method === "POST" ? req.body?.isAvailable !== false : req.body?.isAvailable === true));

const router = Router({ mergeParams: true });

export const SEARCH_RANKING = {
  en: "Search results are sorted by newest listing first, unless you choose another order (price low to high, price high to low, store rating). Only products of approved stores within your delivery reach are shown. No store pays for a better position, and nothing is personalised from your profile.",
  fi: "Hakutulokset järjestetään uusimmasta ilmoituksesta alkaen, ellet valitse toista järjestystä (hinta nousevasti, hinta laskevasti, kaupan arvio). Näytämme vain hyväksyttyjen kauppojen tuotteet toimitusalueeltasi. Kukaan kauppa ei maksa paremmasta sijoituksesta, eikä mitään räätälöidä profiilisi perusteella.",
};
const SEARCH_SORTS = [
  { key: "relevance", label: { en: "Newest first (default)", fi: "Uusimmat ensin (oletus)" } },
  { key: "newest", label: { en: "Newest first", fi: "Uusimmat ensin" } },
  { key: "price_asc", label: { en: "Price: low to high", fi: "Hinta: halvin ensin" } },
  { key: "price_desc", label: { en: "Price: high to low", fi: "Hinta: kallein ensin" } },
  { key: "rating", label: { en: "Store rating", fi: "Kaupan arvio" } },
];

router.get("/stores/:storeId(\\d+)/products", optionalAuth, listProducts);
router.get("/products/search",                searchProducts);
// How search results are sorted (DSA Art. 27 / Omnibus Art. 6a: main ranking parameters), 2.17
router.get("/products/ranking", (_req, res) => res.json({ ok: true, explanation: SEARCH_RANKING, sorts: SEARCH_SORTS }));
router.get("/products/:id(\\d+)",             optionalAuth, getProduct);
router.post("/products",                      auth, requireRole("VENDOR"), publishing, createProduct);
router.patch("/products/:id(\\d+)",           auth, requireRole("VENDOR"), publishing, updateProduct);
router.delete("/products/:id(\\d+)",          auth, requireRole("VENDOR"), deleteProduct);
router.use(productVideoRoutes);

export default router;
