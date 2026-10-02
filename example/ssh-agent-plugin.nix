# Optional third-party plugin used by doc/ssh-agent.md. This derives a new
# recipient from agent signatures; it cannot decrypt existing SSH recipients.
{
  buildGoModule,
  fetchFromGitHub,
  age,
}:
buildGoModule {
  pname = "age-plugin-sshagent";
  version = "0-unstable-2026-06-12";
  src = fetchFromGitHub {
    owner = "eszio";
    repo = "age-plugin-sshagent";
    rev = "8bc67c4a107f7e00d7d2661b740c903df9f673c6";
    hash = "sha256-ogXZ+3bTGE3n+qfo8WeotjT35m2fcGfCcrooAjqzyyU=";
  };
  vendorHash = "sha256-bYx2qwP9FOZFP3a/NldnyU1FcBjdXusNkjvZdyPI1VI=";
  nativeCheckInputs = [ age ];
}
