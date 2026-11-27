<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- No sans-serif and no sans alias, and no gtk-font-name in gtk3/gtk4.ini:
       the desktop does not decide what a GTK or an Electron app draws its own
       chrome with. Each one falls back to its own default face. The desktop
       surfaces name their family directly in the generated Appearance.qml, so
       nothing here has to translate a generic family for them. -->

  <!-- The terminal and code voice, for anything that asks for `monospace`
       instead of naming a family. kitty names the family itself in kitty.conf. -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>{{typography.fonts.mono}}</family>
    </prefer>
  </alias>

  <!-- One weight for the terminal. The panels ask for 600 with font.weight and
       Qt resolves that against the family's own instances; a toolkit that goes
       through fontconfig asks for weight normal and would come out at 400, so a
       request carrying a weight under semibold is raised to 600. The test only
       matches a pattern that HAS a weight: `fc-match FAMILY` with no weight
       prints the 400 face, which is why the check in references/procedures.md
       asks for `FAMILY:weight=normal`. An explicit bold stays bold. -->
  <match target="pattern">
    <test name="family"><string>{{typography.fonts.mono}}</string></test>
    <test name="weight" compare="less"><const>demibold</const></test>
    <edit name="weight" mode="assign"><const>demibold</const></edit>
  </match>
</fontconfig>
