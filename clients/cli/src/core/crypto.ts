/**
 * 密码加密工具 —— 主机密码落本地配置前用 AES-256-GCM 加密，绝不存明文。
 * 1:1 移植自 Java 版 CryptoUtil，密文格式互通。
 *
 * 密文格式：Base64( iv[12] + cipherText + authTag[16] )。
 * Node crypto 的 GCM 把 authTag 单独返回，这里手动拼到密文尾部，与 Java 版
 * （tag 内联在 doFinal 输出尾部）布局一致，两端密文可互相解密。
 *
 * 密钥来源：环境变量 XWSSH_CRYPTO_KEY；任意长度经 SHA-256 派生成 32 字节 AES-256 密钥。
 */
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto'

const ALGO = 'aes-256-gcm'
const IV_LEN = 12 // GCM 推荐 12 字节 IV
const TAG_LEN = 16 // 认证标签 16 字节（128 位）
const DEV_DEFAULT_KEY = 'xwssh-dev-default-key-change-me'

/** 任意密钥串经 SHA-256 派生成固定 32 字节 */
function deriveKey(raw: string): Buffer {
  return createHash('sha256').update(raw, 'utf8').digest()
}

function resolveKey(): Buffer {
  const raw = process.env.XWSSH_CRYPTO_KEY
  if (!raw || raw.trim() === '') {
    // 没配密钥退到开发默认值，仅保证能跑；生产务必设 XWSSH_CRYPTO_KEY
    return deriveKey(DEV_DEFAULT_KEY)
  }
  return deriveKey(raw)
}

/** 加密：明文 → Base64(iv + 密文 + tag)。空串返回 null。 */
export function encrypt(plain: string | null): string | null {
  if (!plain) return null
  const key = resolveKey()
  const iv = randomBytes(IV_LEN)
  const cipher = createCipheriv(ALGO, key, iv, { authTagLength: TAG_LEN })
  const ct = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  // 布局与 Java 版对齐：iv + 密文 + tag
  return Buffer.concat([iv, ct, tag]).toString('base64')
}

/** 解密：Base64(iv + 密文 + tag) → 明文。空串返回 null。 */
export function decrypt(enc: string | null): string | null {
  if (!enc) return null
  const key = resolveKey()
  const all = Buffer.from(enc, 'base64')
  const iv = all.subarray(0, IV_LEN)
  const tag = all.subarray(all.length - TAG_LEN)
  const ct = all.subarray(IV_LEN, all.length - TAG_LEN)
  const decipher = createDecipheriv(ALGO, key, iv, { authTagLength: TAG_LEN })
  decipher.setAuthTag(tag)
  return Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8')
}
