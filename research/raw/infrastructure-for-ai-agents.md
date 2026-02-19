---
title: "Infrastructure for AI Agents"
url: "https://arxiv.org/pdf/2501.10114"
date_fetched: 2026-02-16
---

# Infrastructure for AI Agents

## Title and Authors
**Infrastructure for AI Agents**

Authors: Alan Chan (Centre for the Governance of AI), Kevin Wei (Harvard Law School), Sihao Huang (University of Oxford), Nitarshan Rajkumar (University of Cambridge), Elija Perrier (Australian National University), Seth Lazar (Australian National University), Gillian K. Hadfield (Johns Hopkins University), Markus Anderljung (Centre for the Governance of AI)

Published: arXiv:2501.10114v3, June 19, 2025

---

## Abstract

The paper proposes that AI agents operating in open-ended environments require external technical systems and protocols -- termed "agent infrastructure" -- to mediate their interactions with environments, institutions, and other actors. Rather than relying solely on modifying agent behavior directly, the authors argue that infrastructure similar to internet protocols like HTTPS will be essential for managing agent ecosystems.

The work identifies three core functions for agent infrastructure:

1. **Attribution**: Connecting agent actions to specific agents, users, or other entities
2. **Interaction**: Shaping how agents engage with their environments
3. **Response**: Detecting and remedying harmful agent actions

---

## 1. Introduction

Agents are defined as "AI systems that can plan and execute interactions in open-ended environments." Contemporary language-model-based agents differ from earlier narrowly-scoped systems by attempting diverse tasks like software engineering and office support.

Key distinctions from other AI systems:
- Agents directly interact with digital services, unlike chatbots
- Agents adapt to underspecified instructions, unlike traditional software

The paper acknowledges both beneficial potential (personalized decision-making, productivity gains) and risks (scams, service disruption). While system-level interventions (fine-tuning, adversarial robustness work) are valuable, they cannot fully address how heterogeneous agents will interact with each other and existing institutions.

The traffic safety analogy illustrates the distinction: driver training programs represent system-level interventions, while traffic lights and speed limit enforcement represent infrastructure.

---

## 2. Agent Infrastructure Framework

### 2.1 Categories

Agent infrastructure applies to both individual agent instances (instantiations with specific users, tools, and interaction histories) and broader ecosystems. Implementation can occur within organizations or across organizational boundaries.

### 2.2 Example Use Case: Agent-Run Company

An agent-managed company could utilize:
- **Oversight layers** for human managers to review agent performance
- **Communication protocols** for coordination between agents
- **Identity binding** to establish accountability
- **Rollback mechanisms** to reverse incorrect decisions

### 2.3 Prioritization Considerations

- Infrastructure requiring widespread adoption (inter-agent protocols, IDs) differs from immediately useful tools (oversight layers, rollbacks)
- Some infrastructure only becomes relevant once agents achieve certain capabilities
- Different threat models favor different infrastructure types

---

## 3. Attribution Infrastructure

Attribution infrastructure connects actions, properties, and information to agents, users, or other actors.

### 3.1 Identity Binding

**Description**: Associates agent actions with existing legal entities (humans, corporations), enhancing accountability and enabling existing legal frameworks to apply to agent interactions.

**Definition**: A process of (1) authenticating an identity and (2) linking that identity to an agent instance or its actions.

**Potential Functions**:
- Accountability: Reduces anonymity-enabled attacks like Sybil attacks
- Trust: Counterparties more willing to engage with identifiable agents
- Law application: Enables contract enforcement and legal responsibility attribution

**Existing Alternatives**:
- User authentication systems (banking, OAuth) already attribute some actions
- Metadata and watermarks can carry identity information but face removal risks
- Trusted intermediaries could hold identity information (like ISPs with user data)

**Adoption Pathways**:
- Digital platforms may require binding to prevent fraud
- Extension of existing single sign-on systems
- Natural fit for gig economy agent platforms

**Limitations**:
- Privacy risks from data collection and potential breaches
- Threats to personal safety, whistleblowing, and expression
- Requires proportionate confidentiality protections

**Research Questions**:
- Which action types warrant identity linking?
- How can binding integrate with existing digital identity solutions?
- What access conditions should govern intermediary-held information?

### 3.2 Certification

**Description**: Tools for creating, verifying, and revoking claims about agent properties and behavior, modeled on SSL certificate systems.

**Example Claims**:
- Accessible tools and capabilities
- Autonomy level and human oversight frequency
- Sensitive information handling protocols

**Potential Functions**:
- Trust building for safety-relevant properties
- Market incentives for prosocial agent development
- Supporting recourse mechanisms

**Existing Alternatives**:
- Company auditing (limited if users deploy modified agents)
- Self-reported claims (difficult for counterparties to verify)
- Post-hoc verification of agent outputs

**Adoption Factors**:
- Higher demand in regulated domains (government, healthcare)
- Economic feasibility concerns
- Privacy-preserving verification challenges

**Limitations**:
- Some properties may be impossible to verify
- Risk of false security if guarantees are unfeasible
- Historical precedent of certification capture (TrustARC example)

**Research Questions**:
- Who should make claims and verify them?
- How to verify certificate correspondence with actual agent instances?
- When should certificates be revoked?
- What oversight should govern certifying actors?

### 3.3 Agent IDs

**Description**: Unique identifiers for agent instances, potentially including certifications and bound identities, analogous to serial numbers, tail numbers, or URLs.

**Potential Functions**:
- Supporting certification display
- Incident response and cross-platform tracking
- Enabling targeted interventions on specific agents

**Existing Alternatives**:
- OAuth tokens or API keys (service-specific, limited scope)
- IP addresses (non-static, shared)

**Adoption Pathways**:
- Integration with AI system disclosure obligations
- Requirements from counterparties expecting agent interactions
- CAPTCHA-like methods as transition tools

**Limitations**:
- Enable attacker targeting of particular agents and users
- Information leaks could identify high-value targets
- Vulnerability to compromise and spoofing

**Research Questions**:
- Where should IDs be required?
- How to balance ID functionality with abuse prevention?
- Should IDs link to identifying information?
- How to implement without repeating internet infrastructure problems?

---

## 4. Interaction Infrastructure

Interaction infrastructure shapes how agents engage with environments.

### 4.1 Agent Channels

**Description**: Separate agent traffic from human traffic in digital service interactions, enabling monitoring, incident management, and enforcement of agent-specific rules.

**Design Axes**:
- Software interfaces/protocols versus dedicated internet infrastructure
- Implementation through rate limiting, IP blocks, or separate routing

**Potential Functions**:
- Monitoring macroeconomic agent effects
- Managing incidents (e.g., containing worms)
- Enforcing agent-specific policies
- Reducing attack surface compared to human interfaces
- Supporting ID requirements

**Existing Alternatives**:
- Behavioral testing (unreliable CAPTCHAs)
- Speed-based detection
- Differential service limitations

**Adoption Drivers**:
- Agent efficiency improvements from optimized interfaces
- Higher rate limits and reduced latency
- Time-sensitivity as agents improve at using human interfaces

**Limitations**:
- Effectiveness depends on adoption breadth
- May miss incidents and targeted activity
- Other entities may utilize channels

**Research Questions**:
- Design and implementation specifics?
- What encourages adoption?
- Should all traditional software functionalities have agent channels?
- What policies should govern agent channel use?

### 4.2 Oversight Layers

**Description**: Monitoring systems paired with intervention interfaces enabling actors to intervene in agent operations through action rejection, information provision, or task interruption.

**Potential Functions**:
- Rejecting unsafe actions (fraud prevention)
- Improving functionality (human assistance)
- Accountability documentation
- Insurance design information

**Existing Alternatives**:
- Some agent frameworks include oversight components
- Credit card fraud detection systems
- Unfamiliar device login requests
- Endpoint detection and response tools

**Adoption Considerations**:
- Strong incentives for usability improvement
- Uncertain whether markets will provide socially optimal levels
- Potential conflict with profitable company activities

**Limitations**:
- Flag fatigue from excessive notifications
- Automation bias and insufficient verification
- Cost versus effectiveness tradeoffs
- Market provision uncertainty

**Research Questions**:
- Who should access generated information?
- How to design graceful interruption interfaces?
- How to build trusted automated intervention systems?
- Will markets sufficiently provide oversight layers?

### 4.3 Inter-Agent Communication

**Description**: Rules and technical systems enabling agent-to-agent communication, including point-to-point and broadcast functionalities.

**Potential Functions**:
- Security notifications
- Activity coordination
- Negotiation of interaction rules

**Existing Alternatives**:
- Generic communication infrastructure (Gmail, Facebook Messenger) with limitations
- Meta protocols allowing natural language negotiation before structured formats
- HTTP-based protocols (Google's A2A)

**Adoption Factors**:
- Network effects crucial for standard adoption
- Buy-in from major developers and platforms essential
- Natural language flexibility advantages

**Limitations**:
- Abuse potential (spam, targeting, worms)
- Scammer exploitation
- Ad-supported business preference for ad-resistant protocols
- Alternative business model suppression risks

**Research Questions**:
- Security beyond encryption?
- Broadcasting use cases and design?
- Integration with oversight layers and IDs?
- Steganography and jailbreak prevention?

### 4.4 Commitment Devices

**Description**: Mechanisms enforcing commitments between agents, ranging from smart contracts to escrow arrangements, addressing cooperation and collective action problems.

**Potential Functions**:
- Funding productive activities (Kickstarter-like assurance contracts)
- Tragedy of commons prevention
- Competitive safety investment coordination

**Existing Alternatives**:
- Legal and human norm-based devices (uncertain agent responsiveness)
- Smart contracts on blockchains (limited real-world transaction types)

**Adoption Barriers**:
- Blockchain trust deficits
- Limited transaction type support
- Information oracle problems

**Limitations**:
- Only useful if employed
- Users may circumvent commitments
- Potential negative outcomes from misunderstood preferences
- Cooperative benefits may harm excluded actors

**Research Questions**:
- How to improve smart contract adoption?
- Integration with inter-agent communication?
- Legal enforceability of agent commitments?
- Private actor provision sufficiency?

---

## 5. Response Infrastructure

Response infrastructure detects and remediates harmful agent actions.

### 5.1 Incident Reporting

**Description**: Systems collecting incident information from agents and other actors, filtering for valuable reports, and enabling scalable analysis and response.

**Components**:
1. Agent and actor incident collection tools
2. Spurious report filtering mechanisms
3. Scalable analysis and response methods

**Potential Functions**:
- Improving safety practices through novel harm discovery
- Monitoring locally-run agents without intermediary access

**Existing Alternatives**:
- Limited AI bug bounty programs
- User flagging systems (OpenAI GPTs)
- Civil society reporting systems without enforcement mechanisms
- Historical incident reporting in other domains (aviation, cybersecurity)

**Adoption Considerations**:
- Product improvement incentives
- Reputational damage concerns
- Confidential reporting reduces hesitation
- Government intervention needed for accountability

**Limitations**:
- Anonymous agents limit investigation
- Attacker abuse potential
- Resource scaling challenges

**Research Questions**:
- What incident information is feasible to report?
- How to make systems agent-accessible?
- Which organizations address locally-run incidents?
- Agent roles in incident management?

### 5.2 Rollbacks

**Description**: Mechanisms voiding or undoing agent actions, including both implementation methods and user interfaces for performing or requesting reversals.

**Potential Functions**:
- Undoing unintended actions from malfunction or hijacking
- Minimizing contagion from worms
- Enabling conditional contracting

**Existing Alternatives**:
- Bank fraud reversals
- Social media content takedowns
- Variable domain-specific implementations

**Adoption Considerations**:
- Resistance from those implementing reversals (business uncertainty)
- Potential government intervention (credit card fraud analogy)
- Resource-intensive monitoring and approval
- Clear policy on reversal conditions needed

**Limitations**:
- Physical harm cannot be undone
- Moral hazard risks
- Insurance considerations

**Research Questions**:
- Conditional access based on reliability measures?
- Interaction with insurance systems?
- Business economic effects?
- Abuse prevention?

---

## 6. Challenges and Limitations

### 6.1 Adoption

Network effects determine success for many infrastructure types requiring coordination. Dominant players benefit from incompatibility, creating barriers for smaller competitors. Existing internet standards organizations may play crucial roles.

### 6.2 Lack of Interoperability

Incompatible competing systems (ID systems, protocols) can limit overall utility while benefiting dominant players. Digital Markets Act-style legislation may be necessary.

### 6.3 Lock-In

Widespread adoption of flawed infrastructure creates path dependency challenges. Historical examples like BGP demonstrate slow migration even with identified problems. Procedures for infrastructure updating are essential.

---

## 7. Related Work

The paper builds on:
- Historical agent network protocols (Kahn & Cerf, 1988)
- Foundation-model agent governance literature
- Broader adaptation intervention frameworks
- Multi-agent system risk taxonomies

Agent infrastructure is positioned as a subset of adaptation interventions excluding laws, regulation, and civic initiatives.

---

## 8. Conclusion

Agent infrastructure -- comprising attribution, interaction, and response systems -- provides complementary tools to system-level behavioral modifications. The work is incomplete and architecture-agnostic, with opportunities for researcher investigation, developer implementation, and cross-sector collaboration.

The paper emphasizes that "agent infrastructure is not itself a complete solution, but is rather a platform for policies and norms," requiring engagement across government, industry, and civil society.

---

## Key Tables and Figures

**Table 1**: Summarizes nine research directions across three infrastructure functions

**Table 2**: Compares system-level interventions with infrastructure across domains (AI safety, traffic, health)

**Figures 1-4**: Illustrate infrastructure ecosystem, attribution relationships, interaction mechanisms, and response systems

---

## Acknowledgments

The authors thank 18 individuals for feedback and discussions, representing diverse institutional affiliations.
