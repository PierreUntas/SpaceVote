# VotingPlus - Decentralized Voting System

A robust and secure smart contract for managing decentralized voting sessions on the Ethereum blockchain, with support for multiple sessions and automatic tie-breaking mechanism.

![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Tests](https://img.shields.io/badge/Tests-28%20passed-brightgreen)
![Coverage](https://img.shields.io/badge/Coverage-95.43%25-brightgreen)

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Usage](#usage)
- [Workflow](#workflow)
- [Functions](#functions)
- [Events](#events)
- [Security](#security)
- [Testing](#testing)
- [Gas Report](#gas-report)
- [License](#license)

## Features

- **Multiple Voting Sessions**: Create and manage multiple independent voting sessions
- **Tie-Breaking Mechanism**: Automatic creation of a new session when votes are tied
- **Batch Registration**: Register multiple voters in a single transaction
- **Pausable**: Emergency pause functionality for security
- **Session Cancellation**: Ability to cancel sessions before completion
- **Comprehensive Events**: Full audit trail with indexed events
- **Gas Optimized**: Efficient storage and batch operations

## Architecture

### Workflow States

```text
RegisteringVoters -> ProposalsRegistrationStarted -> ProposalsRegistrationEnded
                                                              |
                                                              v
                         VotesTallied <- VotingSessionEnded <- VotingSessionStarted
                              |
                              v
                     (if tie) -> New Session Created
```

### Key Structures

```solidity
struct Voter {
    bool isRegistered;
    bool hasVoted;
    uint voteProposalId;
}

struct Proposal {
    string description;
    uint voteCount;
}

struct VotingSession {
    uint id;
    uint parentSessionId;
    uint childSessionId;
    bool exists;
    bool isCancelled;
    uint highestVoteCount;
    uint winningProposalId;
    bool hasWinner;
    WorkflowStatus workflowStatus;
    Proposal[] proposals;
    mapping(address => Voter) voters;
    address[] voterAddresses;
}
```

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Setup

```bash
git clone https://github.com/your-username/SpaceVote.git
cd SpaceVote
forge install
forge build
```

## Usage

### Deploy

```bash
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Interact with the Contract

```bash
cast send $CONTRACT_ADDRESS "createVotingSession()" --private-key $PRIVATE_KEY
cast send $CONTRACT_ADDRESS "registerVoter(uint256,address)" 0 0x123... --private-key $PRIVATE_KEY
cast call $CONTRACT_ADDRESS "getSessionStats(uint256)" 0
```

## Workflow

### 1. Create a Voting Session
```solidity
voting.createVotingSession();
```

### 2. Register Voters
```solidity
voting.registerVoter(sessionId, voterAddress);
voting.registerVotersBatch(sessionId, votersArray);
```

### 3. Start Proposal Registration
```solidity
voting.startProposalsRegistration(sessionId);
```

### 4. Submit Proposals (as registered voter)
```solidity
voting.sendNewProposition(sessionId, "My proposal description");
```

### 5. End Proposal Registration
```solidity
voting.endProposalsRegistration(sessionId);
```

### 6. Start Voting
```solidity
voting.startVotingSession(sessionId);
```

### 7. Cast Votes (as registered voter)
```solidity
voting.sendVote(sessionId, proposalId);
```

### 8. End Voting
```solidity
voting.endVotingSession(sessionId);
```

### 9. Tally Votes
```solidity
voting.computeMostVotedProposal(sessionId);
```

### 10. Get Winner
```solidity
Proposal memory winner = voting.getMostVotedProposal(sessionId);
```

## Functions

### Admin Functions (onlyOwner)

| Function | Description |
|----------|-------------|
| `createVotingSession()` | Creates a new voting session |
| `registerVoter(uint, address)` | Registers a single voter |
| `registerVotersBatch(uint, address[])` | Registers multiple voters |
| `startProposalsRegistration(uint)` | Starts proposal phase |
| `endProposalsRegistration(uint)` | Ends proposal phase |
| `startVotingSession(uint)` | Starts voting phase |
| `endVotingSession(uint)` | Ends voting phase |
| `computeMostVotedProposal(uint)` | Tallies votes and determines winner |
| `cancelSession(uint)` | Cancels a session |
| `pause()` | Pauses the contract |
| `unpause()` | Unpauses the contract |

### Voter Functions

| Function | Description |
|----------|-------------|
| `sendNewProposition(uint, string)` | Submits a new proposal |
| `sendVote(uint, uint)` | Casts a vote for a proposal |

### View Functions

| Function | Description |
|----------|-------------|
| `getMostVotedProposal(uint)` | Returns the winning proposal |
| `getAllProposals(uint)` | Returns all proposals |
| `getProposalById(uint, uint)` | Returns a specific proposal |
| `getVoterInfo(uint, address)` | Returns voter information |
| `getVoterAddresses(uint)` | Returns all registered voters |
| `getSessionStats(uint)` | Returns session statistics |
| `getWorkflowStatus(uint)` | Returns current workflow status |
| `getVotingSessionCount()` | Returns total session count |
| `isRegistered(uint, address)` | Checks if address is registered |
| `hasVoted(uint, address)` | Checks if voter has voted |
| `isSessionCancelled(uint)` | Checks if session is cancelled |

## Events

| Event | Description |
|-------|-------------|
| `NewVotingSession(uint indexed)` | New session created |
| `VoterRegistered(uint indexed, address indexed)` | Voter registered |
| `WorkflowStatusChange(uint indexed, status, status)` | Status changed |
| `ProposalRegistered(uint indexed, uint, address indexed)` | Proposal submitted |
| `Voted(uint indexed, address indexed, uint)` | Vote cast |
| `WinningProposition(uint indexed, uint)` | Winner determined |
| `RenewSession(uint indexed, uint indexed)` | Tie-break session created |
| `SessionCancelled(uint indexed)` | Session cancelled |
| `VotersRegisteredBatch(uint indexed, uint)` | Batch registration |

## Security

### Access Control
- Admin functions protected with `onlyOwner` modifier
- Voter-only functions check registration status

### Safety Measures
- `Pausable`: Emergency stop mechanism
- `whenNotPaused`: Protection on state-changing functions
- Session cancellation with `isCancelled` checks
- Bounds checking on arrays
- Zero address validation

### Limits (DoS Protection)

| Constant | Value |
|----------|-------|
| `MAX_PROPOSALS` | 100 |
| `MAX_VOTERS` | 500 |
| `MAX_BATCH_SIZE` | 100 |
| `MIN_DESCRIPTION_LENGTH` | 10 |
| `MAX_DESCRIPTION_LENGTH` | 500 |

## Testing

```bash
forge test
forge test -vvv
forge test --gas-report
forge coverage
```

### Test Results

```text
Suite result: ok. 28 passed; 0 failed; 0 skipped
```

### Coverage

| File | Lines | Statements | Branches | Functions |
|------|-------|------------|----------|-----------|
| Voting.sol | 95.43% | 78.88% | 26.15% | 100% |

## Gas Report

| Function | Min | Avg | Max |
|----------|-----|-----|-----|
| createVotingSession | 23,773 | 68,723 | 74,765 |
| registerVoter | 24,639 | 82,590 | 97,915 |
| registerVotersBatch | 40,275 | 115,496 | 190,717 |
| sendNewProposition | 31,900 | 73,329 | 104,014 |
| sendVote | 29,131 | 69,913 | 85,800 |
| computeMostVotedProposal | 45,797 | 147,171 | 347,333 |

## License

This project is licensed under the MIT License.

---

Built with love by SpaceVote Team

