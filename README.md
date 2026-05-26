# 🧬 LifeLine Protocol

**A Proof-of-Life Inheritance Protocol on Celo. Zero Counterparty Risk.**

LifeLine Protocol is a decentralized, time-locked vault system built for the Celo ecosystem. It utilizes an on-chain Proof-of-Life mechanism, allowing users to lock CELO or USDC into a smart contract that automatically releases funds to a designated beneficiary if the owner fails to "ping" the contract within a custom inactivity window.

## 📸 Interface

*(Drag and drop your screenshots below)*

![Dashboard Screenshot]<img width="1731" height="864" alt="image" src="https://github.com/user-attachments/assets/61c2c447-b10e-4fdf-85e2-76f56c49d81a" />


![Claim Flow Screenshot]<img width="1731" height="864" alt="image" src="https://github.com/user-attachments/assets/b6426fe0-14b5-426b-964e-97720aaecc28" />


## ⚡ Core Features

* **Trustless Inheritance:** Users define a custom inactivity duration (e.g., 30 days, 6 months). If the vault is not pinged by the owner, proving their active presence, the assets become claimable by the heir.
* **Dual Claim Architecture:**
    * *Wallet-to-Wallet:* Direct EVM address targeting for Web3-native heirs.
    * *Email-to-Wallet (Web2 Onboarding):* Generates an ephemeral EVM keypair, encrypts the private key using AES-CBC with a 6-digit PIN, and dispatches the claim link via EmailJS. The heir needs zero Web3 knowledge until the moment of claiming.
* **MiniPay Optimized:** Full JavaScript interoperability (`dart:js_interop`) to seamlessly detect and inject the `window.ethereum` provider specifically for Opera MiniPay and mobile Web3 wallets.
* **Atomic Sweeping:** Claiming an email vault triggers a decentralized transaction that unlocks the vault and sweeps the ERC20 tokens directly into the heir's wallet in one seamless flow.

## 🔗 Smart Contract (Celo Mainnet)
**Contract Address:** `0x4ceb4f21b69cba6c67c03f17c56a5c42e51b4bc1`
* **Supported Assets:** CELO (`0x471EcE...`), USDC (`0xcebA93...`)
* **Network:** Celo Mainnet (Chain ID: 42220)

## 🛠️ Technical Stack
* **Frontend:** Flutter Web (Dart)
* **Web3 Integration:** `webthree` package + custom JS Interop for robust EVM provider injection.
* **Cryptography:** `encrypt` (AES-CBC encryption for ephemeral keys), `crypto` (SHA-256 PIN hashing).
* **Infrastructure:** Alchemy RPC, EmailJS (Off-chain dispatching).

## 🚀 How it Works

1. **Connect:** Open the live web app in an EVM-compatible browser or MiniPay.
2. **Lock Funds:** Click "+ New Vault", select an asset (USDC/CELO), and set an inactivity timer.
3. **The Web2 Flow:** Select "Email Claim", enter an email address, and set a 6-digit PIN.
4. **Trigger & Claim:** Once the timer expires, the protocol dispatches the claim link via email. The beneficiary enters the PIN to decrypt the ephemeral key and safely sweep the funds on-chain.

---
*Securing digital legacies on-chain.*
