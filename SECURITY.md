# Security

Casberi holds keys and signs transactions. If you find a way to move someone's money, read their keys, or make the app show one thing and sign another, please tell us privately first.

## Reporting a vulnerability

Use GitHub's private reporting: the **Security** tab of this repository, then **Report a vulnerability**. Please do not open a public issue.

Include what you did, what happened, and the build you saw it on (Settings shows the version).

## Scope

- The iOS and Mac app in `Casberi/`.
- The account's signing path: `Model/YourAccount*.swift`, `Model/Safe*.swift`, `Screens/Move*.swift`.

The contracts the account runs on are Safe's, Rhinestone's and the ERC-4337 EntryPoint, already deployed and audited by their authors. Report a contract bug to them; tell us too if Casberi uses the contract wrongly.

There is no bug bounty.
