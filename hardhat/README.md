# GuardedExecModule Scripts for Base Network

### Setup

1. **Install dependencies:**
   ```bash
   cd hardhat
   pnpm install
   ```

2. **Configure environment:**
   ```bash
   cp env.example .env
   # Edit .env with your Base RPC URL and private key
   ```

4. **Deploy and test (full flow):**   
   # Create Safe smart account
   pnpm run create-safe-account
   
   # Install GuardedExecModule
   pnpm run install-upgradeable-module
