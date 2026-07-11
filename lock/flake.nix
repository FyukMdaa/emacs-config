{
  description = "THIS IS AN AUTO-GENERATED FILE. PLEASE DON'T EDIT IT MANUALLY.";
  inputs = {
    compat = {
      flake = false;
      owner = "emacs-compat";
      repo = "compat";
      type = "github";
    };
    minions = {
      flake = false;
      owner = "tarsius";
      repo = "minions";
      type = "github";
    };
    mlscroll = {
      flake = false;
      owner = "jdtsmith";
      repo = "mlscroll";
      type = "github";
    };
    modus-themes = {
      flake = false;
      owner = "protesilaos";
      repo = "modus-themes";
      type = "github";
    };
    moody = {
      flake = false;
      owner = "tarsius";
      repo = "moody";
      type = "github";
    };
    nano-modeline = {
      flake = false;
      owner = "rougier";
      repo = "nano-modeline";
      type = "github";
    };
    setup = {
      flake = false;
      type = "git";
      url = "https://codeberg.org/pkal/setup.el";
    };
    twist = {
      flake = false;
      owner = "emacs-twist";
      repo = "twist.el";
      type = "github";
    };
    which-key = {
      flake = false;
      owner = "justbur";
      repo = "emacs-which-key";
      type = "github";
    };
  };
  outputs = { ... }: { };
}
