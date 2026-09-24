# Connect a self-hosted Hermes server

Wing uses your Hermes **dashboard** and **Desktop Gateway**. It does not connect with a model-provider API key or the older API-only service. Set up Hermes and confirm a profile can answer on the host before connecting your phone. Follow the [official Hermes dashboard guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard) for installation, authentication and current launch options.

## Make the dashboard reachable

Start the dashboard on an address your phone can reach. The default `127.0.0.1` address is only available on the host; `localhost` on your phone means the phone itself. Keep the dashboard running after you close your terminal.

Use an encrypted private network or HTTPS for remote access. The official guide recommends Nous Portal sign-in for an internet-facing dashboard; its username/password provider is intended for a trusted network or VPN. Keep model-provider keys on Hermes. Wing needs the dashboard's sign-in, which may be different.

## Add the address in Wing

Choose **Connect your agent → Use an address** and enter the complete dashboard base URL, for example `http://hermes.home:9119` or `https://hermes.example.com/hermes`. Include a custom port or proxy path if your setup uses one. Do not add `/api/ws`; Wing finds the live-chat endpoint itself.

Enter the dashboard username and password if your server uses them. **Custom setup** is for deployments that need extra proxy headers, proxy-managed sign-in or a separate chat address. Review a separate chat address carefully: it receives your chat authentication and any configured access headers. Most setups can leave Custom setup alone.

Tap **Check connection**. Wing checks profile access, the authenticated chat connection and session history separately. When all three pass, name the connection and tap **Save and open**. Send a message to verify your model provider too; a connection check does not run the model.

## Connection help

| What you see | What to check |
| --- | --- |
| Dashboard unreachable | Address, port, VPN, firewall and whether Hermes is still running. Try the dashboard URL in your phone's browser. |
| Sign-in fails | Dashboard credentials and any access proxy. Model-provider keys are different. |
| Profiles load, but live chat fails | Your proxy must forward WebSocket connections to the same Hermes installation. Check its `/api/ws` route. |
| Redirect error | Enter the dashboard's final URL directly. Wing does not forward credentials through redirects. |
| Connected, but no reply | Confirm the selected Hermes profile can answer on the host and its model provider is configured. |

For more detail, see [connection diagnostics](CONNECTION_DIAGNOSTICS_AND_VERSIONS.md). When reporting a problem, include the Wing version, Android version and redacted error; do not share passwords, tokens or private chat content. [Reporting guidance](../SECURITY.md).
