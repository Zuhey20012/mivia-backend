import { v2 as cloudinary } from "cloudinary";
import { env } from "./env";

cloudinary.config({
  cloud_name: env.cloudinaryCloud,
  api_key:    env.cloudinaryKey,
  api_secret: env.cloudinarySecret,
});

export { cloudinary };
