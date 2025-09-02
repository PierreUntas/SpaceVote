// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract VotingPlus is Ownable {

    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }
    
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
        bool exists;
        uint highestVoteCount;
        uint winningProposalId;
        bool hasWinner;
        WorkflowStatus workflowStatus;
        Proposal[] proposals;
        mapping(address => Voter) voters;
    }

    mapping(uint => VotingSession) votingSessions;
    uint votingSessionIdCounter;

    event NewVotingSession(uint votingSessionId);
    event VoterRegistered(uint votingSessionId, address voterAddress);
    event WorkflowStatusChange(uint votingSessionId, WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint votingSessionId, uint proposalId, address submitter);
    event Voted(uint votingSessionId, address voter, uint proposalId);
    event WinningProposition(uint votingSessionId, uint proposalId);
    event RenewSession(uint parentSessionId, uint votingSessionId);

    error VotingSessionDoesNotExist(uint _votingSessionId);
    error VoterRegistrationHasNotStarted();
    error VoterIsNotRegistered(address _address);
    error DescriptionIsEmpty();
    error ProposalRegistrationHasNotStarted();
    error NoProposalsHasBeenRegistered();
    error ProposalRegistrationHasNotEnded();
    error ProposalDoesNotExist(uint _proposalId);
    error VotingHasNotStarted(); 
    error UserHasAlreadyVoted(address _address);
    error NoVotesHasBeenRegistered();
    error VotingHasNotEnded();
    error VotingSessionHasWinner();
    
    constructor() Ownable(msg.sender) {}

    function createVotingSession() external onlyOwner {
        VotingSession storage newVotingSession = votingSessions[votingSessionIdCounter];
        newVotingSession.id = votingSessionIdCounter;
        newVotingSession.exists = true;
        emit NewVotingSession(votingSessionIdCounter);
        votingSessionIdCounter++;
    }

    function renewSession(uint _parentSessionId, Proposal[] memory _bestProposals) internal {
        VotingSession storage newVotingSession = votingSessions[votingSessionIdCounter];
        newVotingSession.id = votingSessionIdCounter;
        newVotingSession.parentSessionId = _parentSessionId;
        newVotingSession.exists = true;
        for (uint i = 0; i < _bestProposals.length; i++) {
            newVotingSession.proposals.push(_bestProposals[i]);
        }
        emit RenewSession(_parentSessionId, votingSessionIdCounter);
        votingSessionIdCounter++;
    }

    function registerVoter(uint _votingSessionId, address _address) external onlyOwner {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.workflowStatus != WorkflowStatus.RegisteringVoters) revert VoterRegistrationHasNotStarted();
        Voter storage voter = currentVotingSession.voters[_address];
        voter.isRegistered = true;
        emit VoterRegistered(_votingSessionId, _address);
    }

    function startProposalsRegistration(uint _votingSessionId) external onlyOwner {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.workflowStatus != WorkflowStatus.RegisteringVoters) revert VoterRegistrationHasNotStarted();
        currentVotingSession.workflowStatus = WorkflowStatus.ProposalsRegistrationStarted;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.RegisteringVoters, WorkflowStatus.ProposalsRegistrationStarted);
    }

    function sendNewProposition(uint _votingSessionId, string memory _description) external {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.workflowStatus != WorkflowStatus.ProposalsRegistrationStarted) revert ProposalRegistrationHasNotStarted();
        if (!currentVotingSession.voters[msg.sender].isRegistered) revert VoterIsNotRegistered(msg.sender);
        if (bytes(_description).length == 0) revert DescriptionIsEmpty();
        currentVotingSession.proposals.push(Proposal(_description, 0));
        emit ProposalRegistered(_votingSessionId, currentVotingSession.proposals.length - 1, msg.sender);
    }
    
    function endProposalsRegistration(uint _votingSessionId) external onlyOwner {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.workflowStatus != WorkflowStatus.ProposalsRegistrationStarted) revert ProposalRegistrationHasNotStarted();
        if (currentVotingSession.proposals.length == 0) revert NoProposalsHasBeenRegistered();
        currentVotingSession.workflowStatus = WorkflowStatus.ProposalsRegistrationEnded;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.ProposalsRegistrationStarted, WorkflowStatus.ProposalsRegistrationEnded); 
    }

    function startVotingSession(uint _votingSessionId) external onlyOwner {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.workflowStatus != WorkflowStatus.ProposalsRegistrationEnded) revert ProposalRegistrationHasNotEnded();
        currentVotingSession.workflowStatus = WorkflowStatus.VotingSessionStarted;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.ProposalsRegistrationEnded, WorkflowStatus.VotingSessionStarted); 
    }
    
    function sendVote(uint _votingSessionId, uint _proposalId) external {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (_proposalId >= currentVotingSession.proposals.length) revert ProposalDoesNotExist(_proposalId);
        if (currentVotingSession.workflowStatus != WorkflowStatus.VotingSessionStarted) revert VotingHasNotStarted();
        Voter storage voter = currentVotingSession.voters[msg.sender];
        if (!voter.isRegistered) revert VoterIsNotRegistered(msg.sender);
        if (voter.hasVoted) revert UserHasAlreadyVoted(msg.sender);
        Proposal storage proposal = currentVotingSession.proposals[_proposalId];
        proposal.voteCount++;
        voter.hasVoted = true;
        voter.voteProposalId = _proposalId;
        if (proposal.voteCount > currentVotingSession.highestVoteCount) {
            currentVotingSession.highestVoteCount = proposal.voteCount;
        }
        emit Voted(_votingSessionId,msg.sender, _proposalId);
    }

    function endVotingSession(uint _votingSessionId) external onlyOwner {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.workflowStatus != WorkflowStatus.VotingSessionStarted) revert VotingHasNotStarted();
        if (currentVotingSession.highestVoteCount == 0) revert NoVotesHasBeenRegistered();
        currentVotingSession.workflowStatus = WorkflowStatus.VotingSessionEnded;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.VotingSessionStarted, WorkflowStatus.VotingSessionEnded);
    }

    function computeMostVotedProposal(uint _votingSessionId) external onlyOwner {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.workflowStatus != WorkflowStatus.VotingSessionEnded) revert VotingHasNotEnded();
        
        Proposal[] storage proposals = currentVotingSession.proposals;
        uint numberOfBestProposal;

        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].voteCount == currentVotingSession.highestVoteCount) {
                numberOfBestProposal++;
            }
        }

        if (numberOfBestProposal == 1) {
            for (uint i = 0; i < proposals.length; i++) {
                if (proposals[i].voteCount == currentVotingSession.highestVoteCount) {
                    currentVotingSession.winningProposalId = i;
                    emit WinningProposition(_votingSessionId, i);
                    break;
                }
            }
            currentVotingSession.hasWinner = true;
            currentVotingSession.workflowStatus = WorkflowStatus.VotesTallied;
            return;
        }

        Proposal[] memory bestProposals = new Proposal[](numberOfBestProposal);
        uint index;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].voteCount == currentVotingSession.highestVoteCount) {
                bestProposals[index] = proposals[i];
                index++;
            }
        }
        renewSession(currentVotingSession.id, bestProposals);
    }

    function getMostVotedProposal(uint _votingSessionId) external view returns(Proposal memory) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (!currentVotingSession.hasWinner) revert VotingSessionHasWinner();
        return currentVotingSession.proposals[currentVotingSession.winningProposalId];
    }

    function getParentVotingSessionId(uint _votingSessionId) external view returns(uint) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        return votingSessions[_votingSessionId].parentSessionId;
    }

    function getAllProposals(uint _votingSessionId) external view returns(Proposal[] memory) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        return currentVotingSession.proposals;
    }

    function getProposalById(uint _votingSessionId, uint _proposalId) external view returns(Proposal memory) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        return currentVotingSession.proposals[_proposalId];
    }

    function isRegistered(uint _votingSessionId, address _address) external view returns(bool) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        return currentVotingSession.voters[_address].isRegistered;
    }

    function getWorkflowStatus(uint _votingSessionId) external view returns(WorkflowStatus) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        return currentVotingSession.workflowStatus;
    }
}