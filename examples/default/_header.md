# Default example

A resource group, a virtual network with the runners' subnet, a Key Vault with the secret for the GitHub
App's private key, and organization runners in the runner group `mlz`, with no instances. After a person has
put the App's key in the secret, raising `instances` boots runners that register with GitHub.

Fortytwo's image is billed per instance and hour, and its terms must be accepted in the subscription first
(`az vm image terms accept --publisher amestofortytwoas1653635920536 --offer self_hosted_runner_github --plan ubuntu-latest-gen2`).

Run it with `scripts/e2e.sh examples/default`: apply, a second plan that must be empty, destroy.
