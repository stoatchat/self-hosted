// THIS FILE IS TAILORED TO STOAT PRODUCTION
// MIGRATING FROM A BACKUP & EXISTING CDN NODE
// INTO BACKBLAZE B2
//
// THIS IS ONLY INCLUDED FOR REFERENCE PURPOSES

// NODE_EXTRA_CA_CERTS=~/projects/revolt-admin-panel/revolt.crt node index.mjs
// NODE_EXTRA_CA_CERTS=/cwd/revolt.crt node /cwd/index.mjs

import { readdir, readFile, writeFile } from "node:fs/promises";
import { createCipheriv, createHash, randomBytes } from "node:crypto";
import { resolve } from "node:path";
import { MongoClient } from "mongodb";
import { config } from "dotenv";
import assert from "node:assert";
import bfj from "bfj";
config();
config({ path: "/cwd/.env" });

import BackBlazeB2 from "backblaze-b2";
import axiosRetry from "axios-retry";
import { decodeTime } from "ulid";

// .env:
// ENCRYPTION_KEY=
// MONGODB=
// B2_APP_KEYID=
// B2_APP_KEY=

/**
 * @type {string | null}
 */
const USE_CACHE = "/cwd/cache.json";
let processed_ids = new Set();

async function dumpCache() {
  if (USE_CACHE) await bfj.write(USE_CACHE, [...processed_ids]);
}

if (USE_CACHE) {
  try {
    processed_ids = new Set(await bfj.read(USE_CACHE));
  } catch (err) {
    console.error(err);
  }
}

const b2 = new BackBlazeB2({
  applicationKeyId: process.env.B2_APP_KEYID,
  applicationKey: process.env.B2_APP_KEY,
  retry: {
    retryDelay: axiosRetry.exponentialDelay,
  },
});

await b2.authorize();

//const encKey = Buffer.from(randomBytes(32), "utf8");
//console.info(encKey.toString("base64"));
const encKey = Buffer.from(process.env.ENCRYPTION_KEY, "base64");

const mongo = new MongoClient(process.env.MONGODB);
await mongo.connect();

// TODO: set all existing files to current timestamp
const dirs = [
  // "banners",
  // "emojis", // TODO: timestamps
  // "avatars",
  // "backgrounds",
  // "icons",
  "attachments", // https://stackoverflow.com/a/18777877
];

async function encryptFile(data) {
  const iv = Buffer.from(randomBytes(12), "utf8");
  const cipher = createCipheriv("aes-256-gcm", encKey, iv);

  let enc = cipher.update(data, "utf8", "base64");
  enc += cipher.final("base64");
  //   enc += cipher.getAuthTag();

  enc = Buffer.from(enc, "base64");

  return {
    iv,
    data: Buffer.concat([enc, cipher.getAuthTag()]),
  };
}

const cache = {};

const objectLookup = {};

/**
 * aaa
 */
async function determineUploaderIdAndUse(f, v, i) {
  if (f.tag === "attachments" && v === "attachments") {
    if (typeof f.message_id !== "string") {
      console.warn(i, "No message id specified.");
      return null;
    }

    if (!objectLookup[f.message_id]) {
      objectLookup[f.message_id] = await mongo
        .db("revolt")
        .collection("messages")
        .findOne({
          _id: f.message_id,
        });
    }

    if (!objectLookup[f.message_id]) {
      console.warn(i, "Message", f.message_id, "doesn't exist anymore!");
      return null;
    }

    return {
      uploaded_at: new Date(decodeTime(f.message_id)),
      uploader_id: objectLookup[f.message_id].author,
      used_for: {
        type: "message",
        id: f.message_id,
      },
    };
  } else if (f.tag === "banners" && v === "banners") {
    if (typeof f.server_id !== "string") {
      console.warn(i, "No server id specified.");
      return null;
    }

    if (!objectLookup[f.server_id]) {
      objectLookup[f.server_id] = await mongo
        .db("revolt")
        .collection("servers")
        .findOne({
          _id: f.server_id,
        });
    }

    if (!objectLookup[f.server_id]) {
      console.warn(i, "Server", f.server_id, "doesn't exist anymore!");
      return null;
    }

    return {
      uploaded_at: new Date(),
      uploader_id: objectLookup[f.server_id].owner,
      used_for: {
        type: "serverBanner",
        id: f.server_id,
      },
    };
  } else if (f.tag === "emojis" && v === "emojis") {
    if (typeof f.object_id !== "string") {
      return null;
    }

    if (!objectLookup[f.object_id]) {
      objectLookup[f.object_id] = await mongo
        .db("revolt")
        .collection("emojis")
        .findOne({
          _id: f.object_id,
        });
    }

    if (!objectLookup[f.object_id]) {
      console.warn(i, "Emoji", f.object_id, "doesn't exist anymore!");
      return null;
    }

    return {
      uploaded_at: new Date(decodeTime(f.object_id)),
      uploader_id: objectLookup[f.object_id].creator_id,
      used_for: {
        type: "emoji",
        id: f.object_id,
      },
    };
  } else if (f.tag === "avatars" && v === "avatars") {
    if (typeof f.user_id !== "string") {
      return null;
    }

    if (!objectLookup[f.user_id]) {
      objectLookup[f.user_id] = await mongo
        .db("revolt")
        .collection("users")
        .findOne({
          _id: f.user_id,
        });
    }

    if (!objectLookup[f.user_id]) {
      console.warn(i, "User", f.user_id, "doesn't exist anymore!");
      return null;
    }

    if (objectLookup[f.user_id].avatar?._id !== f._id) {
      console.warn(
        i,
        "Attachment no longer in use.",
        f._id,
        "for",
        f.user_id,
        "current:",
        objectLookup[f.user_id].avatar?._id
      );
      return null;
    }

    return {
      uploaded_at: new Date(),
      uploader_id: f.user_id,
      used_for: {
        type: "userAvatar",
        id: f.user_id,
      },
    };
  } else if (f.tag === "backgrounds" && v === "backgrounds") {
    if (typeof f.user_id !== "string") {
      return null;
    }

    if (!objectLookup[f.user_id]) {
      objectLookup[f.user_id] = await mongo
        .db("revolt")
        .collection("users")
        .findOne({
          _id: f.user_id,
        });
    }

    if (!objectLookup[f.user_id]) {
      console.warn(i, "User", f.user_id, "doesn't exist anymore!");
      return null;
    }

    if (objectLookup[f.user_id].profile?.background?._id !== f._id) {
      console.warn(
        i,
        "Attachment no longer in use.",
        f._id,
        "for",
        f.user_id,
        "current:",
        objectLookup[f.user_id].profile?.background?._id
      );
      return null;
    }

    return {
      uploaded_at: new Date(),
      uploader_id: f.user_id,
      used_for: {
        type: "userProfileBackground",
        id: f.user_id,
      },
    };
  } else if (f.tag === "icons" && v === "icons") {
    if (typeof f.object_id !== "string") {
      return null;
    }

    // some bugged files at start
    // ... expensive to compute at worst case =(
    // so instead we can just disable it until everything is processed
    // then re-run on these!
    if (false) {
      objectLookup[f.object_id] = await mongo
        .db("revolt")
        .collection("users")
        .findOne({
          _id: f.object_id,
        });

      if (!objectLookup[f.object_id]) {
        console.warn(i, "No legacy match!");
        return null;
      }

      return {
        uploaded_at: new Date(),
        uploader_id: f.object_id,
        used_for: {
          type: "legacyGroupIcon",
          id: f.object_id,
        },
      };
    }

    if (!objectLookup[f.object_id]) {
      objectLookup[f.object_id] = await mongo
        .db("revolt")
        .collection("servers")
        .findOne({
          _id: f.object_id,
        });
    }

    if (
      !objectLookup[f.object_id] ||
      // heuristic for not server
      !objectLookup[f.object_id].channels
    ) {
      console.warn(i, "Server", f.object_id, "doesn't exist!");

      if (!objectLookup[f.object_id]) {
        objectLookup[f.object_id] = await mongo
          .db("revolt")
          .collection("channels")
          .findOne({
            _id: f.object_id,
          });
      }

      if (!objectLookup[f.object_id]) {
        console.warn(i, "Channel", f.object_id, "doesn't exist!");
        return null;
      }

      let server;
      const serverId = objectLookup[f.object_id].server;
      if (serverId) {
        server = objectLookup[serverId];

        if (!server) {
          server = await mongo.db("revolt").collection("servers").findOne({
            _id: serverId,
          });

          console.info(
            i,
            "Couldn't find matching server for channel " + f.object_id + "!"
          );
          if (!server) return null;

          objectLookup[serverId] = server;
        }
      }

      return {
        uploaded_at: new Date(),
        uploader_id: (server ?? objectLookup[f.object_id]).owner,
        used_for: {
          type: "channelIcon",
          id: f.object_id,
        },
      };
    }

    return {
      uploaded_at: new Date(),
      uploader_id: objectLookup[f.object_id].owner,
      used_for: {
        type: "serverIcon",
        id: f.object_id,
      },
    };
  } else {
    throw (
      "couldn't find uploader id for " +
      f._id +
      " expected " +
      v +
      " but got " +
      f.tag
    );
  }
}

const workerCount = 8;
let workingOnHashes = [];

for (const dir of dirs) {
  console.info(dir);

  // const RESUME = 869000 + 283000 + 772000;

  // UPLOAD FROM LOCAL FILE LISTING:
  // const RESUME = 0;
  // const files = (await readdir(dir)).slice(RESUME);
  // const total = files.length;

  // UPLOAD FROM DATABASE FILE LISTING:
  const files = await mongo
    .db("revolt")
    .collection("attachments")
    .find(
      {
        tag: dir,
        // don't upload delete files
        deleted: {
          $ne: true,
        },
        // don't upload already processed files
        hash: {
          $exists: false,
        },
      },
      {
        projection: { _id: 1 },
      }
    )
    .toArray()
    .then((arr) => arr.map((x) => x._id));
  const total = files.length;

  let i = 0;
  let skipsA = 0,
    skipsB = 0;

  await Promise.all(
    new Array(workerCount).fill(0).map(async (_) => {
      while (true) {
        const file = files.shift();
        if (!file) return;

        i++;
        console.info(i, files.length, file);
        // if (i < 869000) continue; // TODO
        // if (i > 3000) break;

        if (USE_CACHE) {
          if (processed_ids.has(file)) {
            console.info(i, "Skip, known file.");
            continue;
          }
        }

        const doc = await mongo
          .db("revolt")
          .collection("attachments")
          .findOne({
            _id: file,
            // don't upload delete files
            deleted: {
              $ne: true,
            },
            // don't upload already processed files
            hash: {
              $exists: false,
            },
          });

        if (!doc) {
          console.info(
            i,
            "Skipping as it does not exist in DB, is queued for deletion, or has already been processed!"
          );
          skipsA += 1;
          continue;
        }

        const metaUseInfo = await determineUploaderIdAndUse(doc, dir, i);
        if (!metaUseInfo) {
          if (USE_CACHE) {
            processed_ids.add(file);
          }
          console.info(i, "Skipping as it hasn't been attached to anything!");
          skipsB += 1;
          continue;
        }

        const start = +new Date();

        let buff;
        try {
          buff = await readFile(resolve(dir, file));
        } catch (err) {
          if (err.code === "ENOENT") {
            if (USE_CACHE) {
              processed_ids.add(file);
            }
            console.log(i, "File not found!");
            await mongo.db("revolt").collection("logs").insertOne({
              type: "missingFile",
              desc: "File doesn't exist!",
              file,
            });
            continue;
          } else {
            throw err;
          }
        }

        const hash = createHash("sha256").update(buff).digest("hex");

        while (workingOnHashes.includes(hash)) {
          console.log(
            "Waiting to avoid race condition... hash is already being processed..."
          );

          await new Promise((r) => setTimeout(r, 1000));
        }

        workingOnHashes.push(hash);

        // merge existing
        const existingHash = await mongo
          .db("revolt")
          .collection("attachment_hashes")
          .findOne({
            _id: hash,
          });

        if (existingHash) {
          console.info(i, "Hash already uploaded, merging!");

          await mongo
            .db("revolt")
            .collection("attachments")
            .updateOne(
              {
                _id: file,
              },
              {
                $set: {
                  size: existingHash.size,
                  hash,
                  ...metaUseInfo,
                },
              }
            );

          await mongo.db("revolt").collection("logs").insertOne({
            type: "mergeHash",
            desc: "Merged an existing file!",
            hash: existingHash._id,
            size: existingHash.size,
          });

          workingOnHashes = workingOnHashes.filter((x) => x !== hash);
          continue;
        }

        // encrypt
        const { iv, data } = await encryptFile(buff);
        const end = +new Date();

        console.info(metaUseInfo); // + write hash
        console.info(
          file,
          hash,
          iv,
          `${end - start}ms`,
          buff.byteLength,
          "bytes"
        );

        let retry = true;
        while (retry) {
          try {
            const urlResp = await b2.getUploadUrl({
              bucketId: "---", // revolt-uploads
            });

            await b2.uploadFile({
              uploadUrl: urlResp.data.uploadUrl,
              uploadAuthToken: urlResp.data.authorizationToken,
              fileName: hash,
              data,
              onUploadProgress: (event) => console.info(event),
            });

            await mongo
              .db("revolt")
              .collection("attachment_hashes")
              .insertOne({
                _id: hash,
                processed_hash: hash,

                created_at: new Date(), // TODO on all

                bucket_id: "revolt-uploads",
                path: hash,
                iv: iv.toString("base64"),

                metadata: doc.metadata,
                content_type: doc.content_type,
                size: data.byteLength,
              });

            await mongo
              .db("revolt")
              .collection("attachments")
              .updateOne(
                {
                  _id: file,
                },
                {
                  $set: {
                    size: data.byteLength,
                    hash,
                    ...metaUseInfo,
                  },
                }
              );

            retry = false;
          } catch (err) {
            if (
              (err.isAxiosError &&
                (err.response?.status === 503 ||
                  err.response?.status === 500)) ||
              (err?.code === "ENOTFOUND" && err?.syscall === "getaddrinfo") ||
              (err?.code === "ETIMEDOUT" && err?.syscall === "connect") ||
              (err?.code === "ECONNREFUSED" && err?.syscall === "connect")
            ) {
              console.error(i, err.response.status, "ERROR RETRYING");

              await mongo
                .db("revolt")
                .collection("logs")
                .insertOne({
                  type: "upload503",
                  desc:
                    "Hit status " +
                    (err?.code === "ETIMEDOUT" && err?.syscall === "connect"
                      ? "Network issue (ETIMEDOUT connect)"
                      : err?.code === "ECONNREFUSED" &&
                        err?.syscall === "connect"
                      ? "Network issue (ECONNREFUSED connect)"
                      : err?.code === "ENOTFOUND" &&
                        err?.syscall === "getaddrinfo"
                      ? "DNS issue (ENOTFOUND getaddrinfo)"
                      : err.response?.status) +
                    ", trying a new URL!",
                  hash,
                });

              await new Promise((r) => setTimeout(() => r(), 1500));
            } else {
              await dumpCache().catch(console.error);
              throw err;
            }
          }
        }

        console.info(i, "Successfully uploaded", file, "to S3!");
        console.info(
          "*** ➡️  Processed",
          i,
          "out of",
          total,
          "files",
          ((i / total) * 100).toFixed(2),
          "%"
        );

        workingOnHashes = workingOnHashes.filter((x) => x !== hash);
      }
    })
  );

  console.info("Skips (A):", skipsA, "(B):", skipsB);
  break;
}

await dumpCache().catch(console.error);
process.exit(0);
