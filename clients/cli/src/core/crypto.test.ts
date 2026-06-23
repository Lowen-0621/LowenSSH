import { describe, it, expect } from 'vitest'
import { encrypt, decrypt } from './crypto.js'

describe('CryptoUtil AES-GCM', () => {
  it('加密后能解回原文', () => {
    const plain = 'my-secret-password-123'
    const enc = encrypt(plain)
    expect(enc).not.toBeNull()
    expect(enc).not.toBe(plain)
    expect(decrypt(enc)).toBe(plain)
  })

  it('同一明文每次密文不同（IV 随机）', () => {
    expect(encrypt('same')).not.toBe(encrypt('same'))
  })

  it('空值返回 null', () => {
    expect(encrypt('')).toBeNull()
    expect(encrypt(null)).toBeNull()
    expect(decrypt('')).toBeNull()
    expect(decrypt(null)).toBeNull()
  })

  it('中文密码往返正确', () => {
    const plain = '密码测试🔐'
    expect(decrypt(encrypt(plain))).toBe(plain)
  })

  it('密文被篡改解密抛错（GCM 完整性校验）', () => {
    const enc = encrypt('data')!
    const tampered = enc.slice(0, -4) + (enc.slice(-4) === 'AAAA' ? 'BBBB' : 'AAAA')
    expect(() => decrypt(tampered)).toThrow()
  })
})
