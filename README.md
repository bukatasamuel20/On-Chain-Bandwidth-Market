# 🌐 On-Chain Bandwidth Market

A decentralized marketplace for buying and selling unused data capacity with smart contract-enforced bandwidth sharing on the Stacks blockchain.

## 🚀 Overview

The On-Chain Bandwidth Market enables users to:
- 📡 **List bandwidth**: Offer unused data capacity for sale
- 💰 **Purchase bandwidth**: Buy data capacity from other users
- 🔒 **Smart contract enforcement**: Automated payment and allocation system
- 📊 **Track usage**: Monitor bandwidth sales and purchases

## 🏗️ Contract Features

### Core Functions

#### 🏪 **Create Bandwidth Listing**
```clarity
(create-bandwidth-listing bandwidth-gb price-per-gb duration-blocks)
```
- **bandwidth-gb**: Amount of bandwidth to sell (in GB)
- **price-per-gb**: Price per GB in microSTX
- **duration-blocks**: How long the listing remains active

#### 🛒 **Purchase Bandwidth**
```clarity
(purchase-bandwidth listing-id requested-gb duration-blocks)
```
- **listing-id**: ID of the bandwidth listing
- **requested-gb**: Amount of bandwidth to purchase
- **duration-blocks**: Usage duration in blocks

#### ❌ **Cancel Listing**
```clarity
(cancel-listing listing-id)
```
Only the listing provider can cancel their own listing.

### 📊 Read-Only Functions

- `get-listing`: View bandwidth listing details
- `get-user-allocation`: Check user's bandwidth allocation
- `get-provider-stats`: View provider statistics
- `get-buyer-stats`: View buyer statistics
- `calculate-total-cost`: Calculate purchase cost including fees
- `is-listing-active`: Check if a listing is still active

## 💡 Usage Examples

### 1. Create a Bandwidth Listing

```clarity
;; List 100GB at 1000 microSTX per GB for 1000 blocks
(contract-call? .on-chain-bandwidth-market create-bandwidth-listing u100 u1000 u1000)
```

### 2. Purchase Bandwidth

```clarity
;; Buy 50GB from listing ID 1 for 500 blocks
(contract-call? .on-chain-bandwidth-market purchase-bandwidth u1 u50 u500)
```

### 3. Check Listing Status

```clarity
;; View details of listing ID 1
(contract-call? .on-chain-bandwidth-market get-listing u1)
```

## 🔧 Setup Instructions

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/bukatasamuel20/On-Chain-Bandwidth-Market.git
cd On-Chain-Bandwidth-Market
```

2. **Install dependencies**
```bash
npm install
```

3. **Run tests**
```bash
clarinet test
```

4. **Deploy locally**
```bash
clarinet console
```

### 🧪 Testing

Run the test suite to verify contract functionality:

```bash
clarinet test
```

## 🏛️ Contract Architecture

### Data Structures

- **bandwidth-listings**: Store all bandwidth offers
- **user-allocations**: Track user bandwidth purchases
- **provider-stats**: Provider performance metrics
- **buyer-stats**: Buyer usage statistics

### Key Features

- ⚡ **Automated payments**: Smart contract handles all transactions
- 📈 **Fee mechanism**: Platform fee for sustainability
- 🔄 **Real-time tracking**: Live bandwidth availability
- 🛡️ **Security**: Access control and validation

## 💼 Economics

### Fee Structure
- Platform fee: 1% (adjustable by contract owner)
- Provider receives: 99% of payment
- Platform retains: 1% for operations

### Payment Flow
1. Buyer pays total cost (bandwidth cost + platform fee)
2. Provider receives bandwidth payment
3. Platform fee held in contract
4. Contract owner can withdraw accumulated fees

## 🔐 Security

- Input validation for all parameters
- Access control for administrative functions
- Automatic expiry for listings
- Safe arithmetic operations

## 📝 Development

### Contract Constants
- `platform-fee-rate`: 100 basis points (1%)
- Error codes for different failure scenarios
- Block-based timing for listings and allocations

### Testing locally
```bash
clarinet console
```

Then interact with the contract using the console commands.

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📜 License

This project is licensed under the MIT License.

---

*Built with ❤️ on Stacks blockchain*
