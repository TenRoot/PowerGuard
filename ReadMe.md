*🛡️ PowerGuard Cloud: The Guard of Guards*
<img width="1024" height="1024" alt="image" src="https://github.com/user-attachments/assets/c6c1ed01-41bc-4ae6-9839-bf5d109872f1" />

**PowerGuard Cloud** is an open-source, "invisible" security monitoring solution designed for Entra ID-joined environments. It fills a critical detection gap by providing immutable, cloud-based analysis of PowerShell activity-independent of local EDR agents.


**🏛️ About the Project**

**PowerGuard Cloud** was developed by **Adi Mahluf** and **Yossi Sassi** as an operative security solution born from real-world incident response and threat hunting requirements at **Tenroot Cyber Security**.


**🛡️ The Philosophy: "Guard of Guards"**

Traditional Endpoint Detection and Response (EDR) agents are powerful but reside within the same trust boundary as an attacker. Skilled adversaries prioritize freezing, unhooking, or bypassing EDR visibility.

**PowerGuard Cloud** serves as the **"Guard of Guards"**:

* **Engine-Level Telemetry:** It leverages native Windows PowerShell Transcription, which is difficult to silence without triggering compliance alerts or Intune policy failures.
* **Out-of-Band Analysis:** Detection logic lives in a serverless Azure Function, completely invisible to an attacker on the endpoint.
* **Immutable Logs:** Once transcripts land in Azure Blob Storage, they are "off-box" and write-protected, preventing attackers from deleting evidence.


**💼 Operative Capabilities**

PowerGuard Cloud is more than a TTP scanner; it is a versatile operative tool that any organization can implement to:

* **Endpoint Activity Monitoring:** Gain granular visibility into every command executed on user endpoints across the organization.
* **Anomaly Detection:** Identify suspicious script execution patterns that deviate from standard administrative or user behavior.
* **Custom Keyword Tracking:** Easily adapt the tool to monitor for organization-specific sensitive keywords, restricted project names, or internal file paths to prevent data exfiltration.
* **Signature-Based Alerting:** Instantly detect 180+ known malicious TTPs, including Mimikatz, Rubeus, and BloodHound.


**🚀 Core Features**

* **Serverless Inspection:** Uses Azure Functions for near real-time, cost-effective log scanning.
* **Intune-Ready:** Designed for rapid deployment via Intune or other MDM platforms.
* **Modern Alerting:** Delivers rich, Adaptive Card notifications directly to Microsoft Teams.
* **Privacy-First:** Securely handles telemetry using short-lived, write-only SAS tokens to minimize the blast radius.


**📦 Repository Contents**


|**File**|**Description**|
|-|-|
|PowerGuard\_Cloud\_Guide.pdf|Complete architectural and deployment manual.|
|run.ps1|Azure Function code for scanning transcripts.|
|PS\_TTPs.txt|High-fidelity critical threat signatures.|
|PS\_TTPs\_warning.txt|Heuristic and suspicious activity signatures.|
|PowerGuard\_Upload.ps1|Endpoint agent for secure transcript exfiltration.|
|PowerGuard\_ACLEnforcement.ps1|Hardens local folders to prevent unauthorized log tampering.|



