// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/Voting.sol";

contract VotingPlusTest is Test {
    VotingPlus public voting;

    address public owner = address(this);
    address public voter1 = address(0x1);
    address public voter2 = address(0x2);
    address public voter3 = address(0x3);
    address public nonVoter = address(0x99);

    function setUp() public {
        voting = new VotingPlus();
    }

    // ==================== Session Creation Tests ====================

    function test_CreateVotingSession() public {
        voting.createVotingSession();
        assertEq(voting.getVotingSessionCount(), 1);
    }

    function test_CreateMultipleSessions() public {
        voting.createVotingSession();
        voting.createVotingSession();
        voting.createVotingSession();
        assertEq(voting.getVotingSessionCount(), 3);
    }

    function test_RevertWhen_NonOwnerCreatesSession() public {
        vm.prank(voter1);
        vm.expectRevert();
        voting.createVotingSession();
    }

    // ==================== Voter Registration Tests ====================

    function test_RegisterVoter() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        assertTrue(voting.isRegistered(0, voter1));
    }

    function test_RegisterVotersBatch() public {
        voting.createVotingSession();
        address[] memory voters = new address[](3);
        voters[0] = voter1;
        voters[1] = voter2;
        voters[2] = voter3;

        voting.registerVotersBatch(0, voters);

        assertTrue(voting.isRegistered(0, voter1));
        assertTrue(voting.isRegistered(0, voter2));
        assertTrue(voting.isRegistered(0, voter3));
    }

    function test_RevertWhen_RegisterVoterTwice() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);

        vm.expectRevert(abi.encodeWithSelector(VotingPlus.VoterAlreadyRegistered.selector, voter1));
        voting.registerVoter(0, voter1);
    }

    function test_RevertWhen_RegisterZeroAddress() public {
        voting.createVotingSession();

        vm.expectRevert(VotingPlus.InvalidAddress.selector);
        voting.registerVoter(0, address(0));
    }

    function test_RevertWhen_RegisterVoterInNonExistentSession() public {
        vm.expectRevert(abi.encodeWithSelector(VotingPlus.VotingSessionDoesNotExist.selector, 99));
        voting.registerVoter(99, voter1);
    }

    function test_RevertWhen_BatchSizeTooLarge() public {
        voting.createVotingSession();
        address[] memory voters = new address[](101);
        for (uint i = 0; i < 101; i++) {
            voters[i] = address(uint160(i + 1000));
        }

        vm.expectRevert(abi.encodeWithSelector(VotingPlus.BatchSizeTooLarge.selector, 100));
        voting.registerVotersBatch(0, voters);
    }

    // ==================== Workflow Tests ====================

    function test_StartProposalsRegistration() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.startProposalsRegistration(0);

        assertEq(uint(voting.getWorkflowStatus(0)), uint(VotingPlus.WorkflowStatus.ProposalsRegistrationStarted));
    }

    function test_RevertWhen_StartProposalsWithNoVoters() public {
        voting.createVotingSession();

        vm.expectRevert(VotingPlus.NoVotersRegistered.selector);
        voting.startProposalsRegistration(0);
    }

    function test_FullWorkflow() public {
        // Créer session
        voting.createVotingSession();
        assertEq(uint(voting.getWorkflowStatus(0)), uint(VotingPlus.WorkflowStatus.RegisteringVoters));

        // Enregistrer voters
        voting.registerVoter(0, voter1);
        voting.registerVoter(0, voter2);

        // Démarrer propositions
        voting.startProposalsRegistration(0);
        assertEq(uint(voting.getWorkflowStatus(0)), uint(VotingPlus.WorkflowStatus.ProposalsRegistrationStarted));

        // Soumettre propositions
        vm.prank(voter1);
        voting.sendNewProposition(0, "Proposition A - une bonne idee");

        vm.prank(voter2);
        voting.sendNewProposition(0, "Proposition B - une autre idee");

        // Fin propositions
        voting.endProposalsRegistration(0);
        assertEq(uint(voting.getWorkflowStatus(0)), uint(VotingPlus.WorkflowStatus.ProposalsRegistrationEnded));

        // Démarrer vote
        voting.startVotingSession(0);
        assertEq(uint(voting.getWorkflowStatus(0)), uint(VotingPlus.WorkflowStatus.VotingSessionStarted));

        // Voter
        vm.prank(voter1);
        voting.sendVote(0, 0);

        vm.prank(voter2);
        voting.sendVote(0, 0);

        // Fin vote
        voting.endVotingSession(0);
        assertEq(uint(voting.getWorkflowStatus(0)), uint(VotingPlus.WorkflowStatus.VotingSessionEnded));

        // Comptabiliser
        voting.computeMostVotedProposal(0);
        assertEq(uint(voting.getWorkflowStatus(0)), uint(VotingPlus.WorkflowStatus.VotesTallied));

        // Vérifier gagnant
        VotingPlus.Proposal memory winner = voting.getMostVotedProposal(0);
        assertEq(winner.description, "Proposition A - une bonne idee");
        assertEq(winner.voteCount, 2);
    }

    // ==================== Proposal Tests ====================

    function test_SendProposition() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.startProposalsRegistration(0);

        vm.prank(voter1);
        voting.sendNewProposition(0, "Ma proposition test");

        VotingPlus.Proposal memory prop = voting.getProposalById(0, 0);
        assertEq(prop.description, "Ma proposition test");
        assertEq(prop.voteCount, 0);
    }

    function test_RevertWhen_DescriptionTooShort() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.startProposalsRegistration(0);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(VotingPlus.DescriptionTooShort.selector, 10));
        voting.sendNewProposition(0, "Court");
    }

    function test_RevertWhen_NonVoterSendsProposition() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.startProposalsRegistration(0);

        vm.prank(nonVoter);
        vm.expectRevert(abi.encodeWithSelector(VotingPlus.VoterIsNotRegistered.selector, nonVoter));
        voting.sendNewProposition(0, "Ma proposition test");
    }

    // ==================== Voting Tests ====================

    function test_SendVote() public {
        _setupVotingPhase();

        vm.prank(voter1);
        voting.sendVote(0, 0);

        assertTrue(voting.hasVoted(0, voter1));

        (bool registered, bool voted, uint proposalId) = voting.getVoterInfo(0, voter1);
        assertTrue(registered);
        assertTrue(voted);
        assertEq(proposalId, 0);
    }

    function test_RevertWhen_VoteTwice() public {
        _setupVotingPhase();

        vm.prank(voter1);
        voting.sendVote(0, 0);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(VotingPlus.UserHasAlreadyVoted.selector, voter1));
        voting.sendVote(0, 0);
    }

    function test_RevertWhen_VoteForNonExistentProposal() public {
        _setupVotingPhase();

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(VotingPlus.ProposalDoesNotExist.selector, 99));
        voting.sendVote(0, 99);
    }

    // ==================== Tie-breaking and renewSession Tests ====================

    function test_RenewSessionOnTie() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.registerVoter(0, voter2);
        voting.startProposalsRegistration(0);

        vm.prank(voter1);
        voting.sendNewProposition(0, "Proposition A - premiere idee");

        vm.prank(voter2);
        voting.sendNewProposition(0, "Proposition B - deuxieme idee");

        voting.endProposalsRegistration(0);
        voting.startVotingSession(0);

        // Égalité : chaque voter vote pour sa proposition
        vm.prank(voter1);
        voting.sendVote(0, 0);

        vm.prank(voter2);
        voting.sendVote(0, 1);

        voting.endVotingSession(0);
        voting.computeMostVotedProposal(0);

        // Une nouvelle session devrait être créée
        assertEq(voting.getVotingSessionCount(), 2);

        // La session parente a un childSessionId
        assertEq(voting.getChildVotingSessionId(0), 1);

        // La nouvelle session a la session parente
        assertEq(voting.getParentVotingSessionId(1), 0);

        // La nouvelle session est en phase de vote
        assertEq(uint(voting.getWorkflowStatus(1)), uint(VotingPlus.WorkflowStatus.VotingSessionStarted));

        // Les voters sont copiés
        assertTrue(voting.isRegistered(1, voter1));
        assertTrue(voting.isRegistered(1, voter2));

        // Les propositions sont copiées (seulement celles à égalité)
        VotingPlus.Proposal[] memory props = voting.getAllProposals(1);
        assertEq(props.length, 2);
        assertEq(props[0].voteCount, 0); // Votes remis à 0
    }

    // ==================== Pause Tests ====================

    function test_Pause() public {
        voting.pause();

        vm.expectRevert();
        voting.createVotingSession();
    }

    function test_Unpause() public {
        voting.pause();
        voting.unpause();

        voting.createVotingSession();
        assertEq(voting.getVotingSessionCount(), 1);
    }

    function test_RevertWhen_NonOwnerPauses() public {
        vm.prank(voter1);
        vm.expectRevert();
        voting.pause();
    }

    // ==================== Tests Cancel ====================

    function test_CancelSession() public {
        voting.createVotingSession();
        voting.cancelSession(0);

        assertTrue(voting.isSessionCancelled(0));
    }

    function test_RevertWhen_ActionOnCancelledSession() public {
        voting.createVotingSession();
        voting.cancelSession(0);

        vm.expectRevert(VotingPlus.SessionAlreadyCancelled.selector);
        voting.registerVoter(0, voter1);
    }

    function test_RevertWhen_CancelCompletedSession() public {
        _completeVotingSession();

        vm.expectRevert(VotingPlus.CannotCancelCompletedSession.selector);
        voting.cancelSession(0);
    }

    // ==================== Tests Getters ====================

    function test_GetSessionStats() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.registerVoter(0, voter2);

        (
            uint proposalsCount,
            uint votersCount,
            uint highestVoteCount,
            bool hasWinner,
            uint winningProposalId,
            bool isCancelled,
            VotingPlus.WorkflowStatus status,
            uint parentId,
            uint childId
        ) = voting.getSessionStats(0);

        assertEq(proposalsCount, 0);
        assertEq(votersCount, 2);
        assertEq(highestVoteCount, 0);
        assertFalse(hasWinner);
        assertEq(winningProposalId, 0);
        assertFalse(isCancelled);
        assertEq(uint(status), uint(VotingPlus.WorkflowStatus.RegisteringVoters));
        assertEq(parentId, 0);
        assertEq(childId, 0);
    }

    function test_GetVoterAddresses() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.registerVoter(0, voter2);

        address[] memory voters = voting.getVoterAddresses(0);
        assertEq(voters.length, 2);
        assertEq(voters[0], voter1);
        assertEq(voters[1], voter2);
    }

    function test_GetAllProposals() public {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.startProposalsRegistration(0);

        vm.prank(voter1);
        voting.sendNewProposition(0, "Proposition 1 test");

        vm.prank(voter1);
        voting.sendNewProposition(0, "Proposition 2 test");

        VotingPlus.Proposal[] memory props = voting.getAllProposals(0);
        assertEq(props.length, 2);
        assertEq(props[0].description, "Proposition 1 test");
        assertEq(props[1].description, "Proposition 2 test");
    }

    // ==================== Helpers ====================

    function _setupVotingPhase() internal {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.registerVoter(0, voter2);
        voting.startProposalsRegistration(0);

        vm.prank(voter1);
        voting.sendNewProposition(0, "Proposition A - test proposition");

        vm.prank(voter2);
        voting.sendNewProposition(0, "Proposition B - another test");

        voting.endProposalsRegistration(0);
        voting.startVotingSession(0);
    }

    function _completeVotingSession() internal {
        voting.createVotingSession();
        voting.registerVoter(0, voter1);
        voting.startProposalsRegistration(0);

        vm.prank(voter1);
        voting.sendNewProposition(0, "Unique proposition pour test");

        voting.endProposalsRegistration(0);
        voting.startVotingSession(0);

        vm.prank(voter1);
        voting.sendVote(0, 0);

        voting.endVotingSession(0);
        voting.computeMostVotedProposal(0);
    }
}

