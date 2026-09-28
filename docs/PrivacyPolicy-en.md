# Privacy Policy

bannzai ("we") sets out this Privacy Policy for the handling of user information, including personal information, in the app "Tanzaku" (the macOS app, and the iOS app together with its extensions such as the share sheet, keyboard and shortcuts; together, the "Service").

## Information we handle and how

### Information you enter (stored on your devices and in your own iCloud)

The snippets you save in the Service (titles, bodies, keywords, tags, folders and snippet groups) and your settings are stored on your device and are **never sent to our servers**. We cannot collect or view them.

If you use iCloud, your snippets, folders, tags and snippet groups are stored in your own area of iCloud provided by Apple Inc. (the CloudKit private database) so that they sync between your Mac and iOS devices. Only you can access that area, and we cannot view it. Information stored in iCloud is handled under Apple Inc.'s privacy policy ( https://www.apple.com/legal/privacy/ ).
<!-- source: https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase "Only the user can access their private database, by default. They own all of the database's content and can view and modify that content. Data in the private database isn't visible in the developer portal." -->

Searches, including semantic search, run on your device unless you turn on the optional external semantic search described below. The data used for semantic search is created on each device and is not synced.

- You are responsible for backing up your snippets. We cannot recover snippets lost by replacing or resetting a device, deleting the Service, or deleting the data from iCloud.

### What you type with the keyboard (iOS)

The Service's iOS keyboard neither stores nor sends what you type with it. The keyboard is used only to read your snippets and insert them into the text field.

### Keystroke monitoring (snippet groups on Mac)

Only when you grant permission, the Mac version monitors keystrokes to detect snippet group keywords, and reads the caret position in the text field through the accessibility features. The monitored keystrokes are used only to detect keywords and are neither stored nor sent.

### AI agent integration (MCP, Mac only)

So that AI agents you connect (such as Claude Code) can search, add, update and delete snippets, the Mac version of the Service runs a Model Context Protocol (MCP) server on your Mac. The server accepts connections only from the same Mac (127.0.0.1) and only from clients holding a token issued by the Service.

Snippets you hand to a connected AI agent are handled under the terms and privacy policy of that agent's provider. You choose which AI agents to connect and can revoke a connection in the Service's settings.

### Optional external semantic search (sending to an external AI service; off by default)

Only if you turn on TypeSafe's Jev in the Mac version's settings and enter your own API key, the Service sends your search query and the bodies of the snippets being searched to the API of TypeSafe, Inc. ( https://typesafe.ai/ ) when you search in the launcher. Nothing is sent unless you agree to the explanation shown before turning it on, and you can turn it off at any time. What is sent is handled under the terms and privacy policy of TypeSafe, Inc. We do not receive it.

### Purchasing and checking the license

**The Mac version**'s license is sold through Lemon Squeezy (United States). Lemon Squeezy processes the payment as the merchant of record and obtains the name, email address and payment information you enter when purchasing. We do not receive payment information such as credit card numbers. We receive the purchaser's name, email address and order details (the product purchased, the date and time, the amount and so on) from Lemon Squeezy. Information obtained by Lemon Squeezy is handled under Lemon Squeezy's privacy policy ( https://www.lemonsqueezy.com/privacy ).
<!-- source: https://www.lemonsqueezy.com/buyer-terms "As merchant of record, Lemon Squeezy is an authorized reseller of the product for the Supplier and provides merchant services to facilitate transactions." / footer of the same page "Sold through Link, LLC f/k/a Lemon Squeezy LLC" / https://docs.lemonsqueezy.com/api/orders/the-order-object lists user_name (The full name of the customer.) and user_email (The email address of the customer.) -->

To activate, check and deactivate the license, the Service sends the license key and a name that distinguishes the Mac on which the license is activated to Lemon Squeezy's API. It does not send the contents of your snippets. The license key is stored in the Mac's Keychain.
<!-- source: https://docs.lemonsqueezy.com/api/license-api/activate-license-key lists the activate parameters license_key (The license key to activate.) and instance_name (A label for the new instance to identify it in Lemon Squeezy.) -->

**The iOS version**'s license is sold as an in-app purchase, and the payment is processed by Apple Inc. We do not receive payment information. The purchase status is checked against the App Store purchase history on the device.

### Checking for updates (Mac version)

To check for updates, the Mac version fetches update information from GitHub Pages ( https://bannzai.github.io/tanzaku/ ) and, when an update is available, downloads the new version from GitHub Releases. The contents of your snippets are not sent in this communication. When the Service connects to GitHub Pages, GitHub, Inc. logs the IP address and handles it under the GitHub Privacy Statement ( https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement ).
<!-- source: https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages "When a GitHub Pages site is visited, the visitor's IP address is logged and stored for security purposes, regardless of whether the visitor has signed into GitHub or not." -->

### Information we collect

The Service requires no account, and we do not collect or store your snippets or other data on servers. The Service contains no advertising or analytics SDK. The only personal information we receive is the purchaser information we receive from Lemon Squeezy when you buy the Mac version (see "Purchasing and checking the license" above) and, when you contact us by email or otherwise, your contact details and inquiry.

## Purposes of use

- To provide, maintain, protect and improve the Service, including activating and checking the license and restoring the purchase status
- To send notices about the Service and to respond to inquiries, including those about purchases and licenses
- To respond to conduct that violates our terms or policies for the Service
- To notify you of changes to the terms and policies for the Service

## Retention

- Snippets and related data stay on your device until you delete them in the Service or delete the Service, and, if synced with iCloud, stay in your iCloud until you delete them
- The Mac version's license key stays in the Mac's Keychain until you deactivate the license in the Service
- Purchaser information we receive from Lemon Squeezy is kept as long as necessary to provide the license, respond to inquiries and meet legal obligations. Information obtained by Lemon Squeezy is retained for the period set out in Lemon Squeezy's privacy policy
- Contact details and inquiries are kept as long as we judge necessary as a record of our response, and are then deleted

## Provision to third parties

We do not provide personal information to third parties (including those outside Japan) without your prior consent, except in the following cases:

- When we entrust all or part of the handling of personal information within the scope necessary to achieve the purposes of use (processor: Lemon Squeezy (United States), for selling the Mac version's license, processing payments, and issuing and checking license keys)
- When personal information is provided as part of a business succession due to a merger or other reason
- When cooperation is required with a national or local government body, or a party entrusted by one, in carrying out duties prescribed by law, and obtaining your consent could impede those duties
- Other cases permitted by the Act on the Protection of Personal Information or other laws

## Disclosure, correction, suspension of use and deletion

When you request disclosure, correction, suspension of use or deletion of your personal information under the Act on the Protection of Personal Information, we will respond without delay after confirming that the request comes from you (and will notify you if no such personal information exists), except where we have no obligation under that Act or other laws.

We do not hold snippets and other data stored on your devices and in your iCloud, so you can delete them yourself:

1. Delete snippets in the Service. If you sync with iCloud, the deletion is reflected on your other synced devices and in your iCloud
2. To delete all data, delete all snippets, wait for the sync to finish, and then delete the Service from each device

## Contact

For opinions, questions, complaints or other inquiries about the handling of user information, contact:

- Provider: bannzai
- Email: bannzai.app@gmail.com

## Changes to this Policy

We may change this Policy as needed. Where a change requires your consent under law, the changed Policy applies only to users who have agreed to it in the manner we specify. When we change this Policy, we will announce the effective date and content of the changed Policy in the app or by other appropriate means, or notify you.

Established: September 28, 2026
