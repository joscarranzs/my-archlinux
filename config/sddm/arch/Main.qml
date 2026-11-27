import QtQuick

// The SDDM greeter, in the unlock card's language.
//
// It used to be a terminal-styled screen of its own: a rasterised logo, a row of
// six PNGs recoloured by a script, and pixel sizes baked into the QML. Two
// login surfaces that share nothing is drift, and the PNG set was the reason
// `sddm-assets.py` had to exist at all. The greeter is now the same surface as
// the lock screen -- date, clock, gold rule, one plaque -- drawn from
// GreeterAppearance.qml, which the theme generator writes beside this file.
//
// SDDM runs this in a QQuickView with SizeRootObjectToView, so the root item
// always gets the screen; width/height below are the size it is authored at,
// not a window size somebody picked.
Rectangle {
  id: root

  width: screenModel.geometry(screenModel.primary).width
  height: screenModel.geometry(screenModel.primary).height
  color: appearance.surface

  GreeterAppearance { id: appearance }

  property string currentUser: userModel.lastUser
  property bool failed: false
  property bool verifying: false
  // The clock is live: a greeter can sit for a while, and a plaque that froze at
  // the time it loaded is a screenshot of the past.
  property date now: new Date()

  // The session the greeter will start. The list holds what the .desktop files
  // call themselves ("Hyprland", "Hyprland (uwsm-managed)"), so the search is
  // case-insensitive: the old template looked for a lowercase "hyprland" in a
  // "Hyprland" string, never matched, and silently logged into whatever SDDM
  // remembered last. Plain Hyprland wins over the uwsm-managed entry because
  // uwsm is not installed here, and an entry that cannot start is not a match
  // worth taking.
  property int sessionIndex: {
    var best = -1
    var bestRank = 0
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      var rank = root.sessionRank(name)
      if (rank > bestRank) {
        bestRank = rank
        best = i
      }
    }
    return best >= 0 ? best : sessionModel.lastIndex
  }

  function sessionRank(name) {
    var lowered = name.toLowerCase()
    if (lowered === "hyprland")
      return 3
    if (lowered.indexOf("hyprland") === -1)
      return 0
    return lowered.indexOf("uwsm") === -1 ? 2 : 1
  }

  // One line, one source of truth: the slot says nothing when there is nothing
  // to report, and reserves its height either way so the card never reflows.
  readonly property string statusText: root.verifying
    ? "VERIFYING…"
    : (root.failed ? "INCORRECT PASSWORD" : "")

  // Both the Return key and the plaque call this, so an attempt has one code
  // path. The view closes on success, so `verifying` only has to be cleared on
  // failure -- and by the timer, for the case where nothing answers at all.
  function attempt() {
    if (root.verifying || passwordInput.text === "")
      return
    root.failed = false
    root.verifying = true
    verifyGuard.restart()
    sddm.login(root.currentUser, passwordInput.text, root.sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      verifyGuard.stop()
      root.verifying = false
      root.failed = true
      passwordInput.text = ""
      passwordInput.forceActiveFocus()
      failureTimer.restart()
    }
    function onLoginSucceeded() {
      root.verifying = false
      root.failed = false
    }
  }

  // A rejection clears the line on the next keystroke; an unanswered attempt
  // hands the field back instead of leaving the card disabled in VERIFYING…
  Timer {
    id: failureTimer
    interval: appearance.failureHintMs
    onTriggered: root.failed = false
  }

  Timer {
    id: verifyGuard
    interval: appearance.failureHintMs
    onTriggered: root.verifying = false
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  Column {
    anchors.centerIn: parent
    spacing: appearance.spacingLarge

    // --- date, clock, rule: the plaque header, identical to the lock's
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(root.now, "dddd, MMMM d").toUpperCase()
      renderType: Text.NativeRendering
      font.family: appearance.uiFont
      font.weight: appearance.fontWeightUi
      font.variableAxes: appearance.fontVariableAxesUi
      font.pixelSize: appearance.fontSizeCaption
      font.letterSpacing: appearance.letterSpacingLabel
      color: appearance.accentInk
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatTime(root.now, "hh:mm")
      renderType: Text.NativeRendering
      font.family: appearance.displayFont
      font.weight: appearance.fontWeightDisplay
      font.variableAxes: appearance.fontVariableAxesDisplay
      font.pixelSize: appearance.fontSizeClock
      color: appearance.text
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: appearance.ruleWidth
      height: appearance.ruleThickness
      color: appearance.gilt
    }

    // --- the card
    Rectangle {
      id: card
      objectName: "card"

      width: appearance.cardWidth
      implicitHeight: content.implicitHeight + appearance.contentPad * 2
      radius: appearance.shapeExtraLarge
      color: appearance.surfaceContainer
      border.color: appearance.gilt
      border.width: appearance.borderWidth

      Column {
        id: content
        anchors.fill: parent
        anchors.margins: appearance.contentPad
        spacing: appearance.spacingSmall

        // --- who is logging in
        Row {
          width: parent.width
          spacing: appearance.spacingSmall

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "account_circle"
            color: appearance.textMuted
            renderType: Text.NativeRendering
            font.family: appearance.iconFont
            font.weight: appearance.fontWeightIcons
            font.variableAxes: appearance.fontVariableAxesIcons
            font.pixelSize: appearance.iconSizeLg
          }

          Text {
            width: parent.width - appearance.iconSizeLg - appearance.spacingSmall
            anchors.verticalCenter: parent.verticalCenter
            text: root.currentUser
            elide: Text.ElideRight
            renderType: Text.NativeRendering
            font.family: appearance.uiFont
            font.weight: appearance.fontWeightUi
            font.variableAxes: appearance.fontVariableAxesUi
            font.pixelSize: appearance.fontSizeTitle
            color: appearance.text
          }
        }

        // --- persistent label: the field keeps saying what it wants after the
        // first keystroke, instead of a placeholder that vanishes
        Text {
          objectName: "passwordLabel"
          text: "PASSWORD"
          renderType: Text.NativeRendering
          font.family: appearance.uiFont
          font.weight: appearance.fontWeightUi
          font.variableAxes: appearance.fontVariableAxesUi
          font.pixelSize: appearance.fontSizeSmall
          font.letterSpacing: appearance.letterSpacingLabel
          color: appearance.textMuted
        }

        Rectangle {
          id: passwordField
          objectName: "passwordField"

          width: parent.width
          height: appearance.fieldHeightTall
          radius: appearance.shapeMedium
          color: appearance.surface
          border.color: root.failed
            ? appearance.danger
            : (passwordInput.activeFocus ? appearance.accent : appearance.outline)
          border.width: appearance.borderWidth

          Row {
            anchors.fill: parent
            anchors.leftMargin: appearance.spacingMedium
            anchors.rightMargin: appearance.spacingMedium
            spacing: appearance.spacingSmall

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "lock"
              color: passwordInput.activeFocus ? appearance.accentInk : appearance.textMuted
              renderType: Text.NativeRendering
              font.family: appearance.iconFont
              font.weight: appearance.fontWeightIcons
              font.variableAxes: appearance.fontVariableAxesIcons
              font.pixelSize: appearance.iconSizeMd
            }

            TextInput {
              id: passwordInput
              objectName: "passwordInput"

              width: parent.width - appearance.iconSizeMd - appearance.spacingSmall
              height: parent.height
              verticalAlignment: TextInput.AlignVCenter
              enabled: !root.verifying
              echoMode: TextInput.Password
              inputMethodHints: Qt.ImhSensitiveData
              passwordCharacter: "\u2022"
              renderType: Text.NativeRendering
              font.family: appearance.textFont
              font.weight: appearance.fontWeightText
              font.pixelSize: appearance.fontSizeBody
              font.letterSpacing: appearance.letterSpacingPassword
              color: appearance.text
              selectionColor: appearance.accent
              selectedTextColor: appearance.accentText

              // Block cursor, visible while focused even when empty: a focused
              // field and an idle one must not look the same.
              cursorDelegate: Component {
                Rectangle {
                  width: appearance.cursorWidth
                  height: appearance.cursorHeight
                  color: appearance.accent
                  visible: passwordInput.activeFocus
                }
              }

              onTextChanged: {
                if (text.length > 0) {
                  root.failed = false
                  failureTimer.stop()
                }
              }

              Keys.onPressed: {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.attempt()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape
                           || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                  text = ""
                  event.accepted = true
                }
              }
            }
          }
        }

        // --- reserved status slot: the ink is never dimmed, the string simply
        // has nothing to say when the attempt has not gone wrong
        Item {
          width: parent.width
          height: appearance.statusHeight

          Text {
            objectName: "statusText"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            color: root.failed ? appearance.danger : appearance.textMuted
            renderType: Text.NativeRendering
            font.family: appearance.uiFont
            font.weight: appearance.fontWeightUi
            font.variableAxes: appearance.fontVariableAxesUi
            font.pixelSize: appearance.fontSizeSmall
            font.letterSpacing: appearance.letterSpacingCaption
          }
        }

        // --- action: the unlock button's recipe, one rung at a time
        Rectangle {
          id: submitButton
          objectName: "submitButton"

          width: parent.width
          height: appearance.buttonHeightLarge
          radius: appearance.shapeFull
          color: submitButton.armed
            ? appearance.accent
            : (submitMouse.pressed ? appearance.pressFill
              : (submitHover.hovered ? appearance.hoverFillHigh
                : appearance.surfaceContainerHigh))
          border.width: appearance.borderWidth
          border.color: submitButton.armed
            ? appearance.accent
            : (submitHover.hovered || submitMouse.pressed
              ? appearance.gilt : appearance.outline)

          readonly property bool armed: !root.verifying && passwordInput.text !== ""

          Behavior on color {
            ColorAnimation {
              duration: appearance.motionControlDuration
              easing.type: appearance.motionControlEasing
            }
          }

          // State layer: only the accent fill needs one, because it is the one
          // fill with no rung above it on the tonal ladder.
          Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: appearance.accentText
            opacity: submitButton.armed && submitHover.hovered
              ? appearance.opacityStateLayer : 0

            Behavior on opacity {
              NumberAnimation {
                duration: appearance.motionControlDuration
                easing.type: appearance.motionControlEasing
              }
            }
          }

          Row {
            anchors.centerIn: parent
            spacing: appearance.spacingSmall

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "arrow_forward"
              color: submitButton.armed ? appearance.accentText : appearance.textMuted
              renderType: Text.NativeRendering
              font.family: appearance.iconFont
              font.weight: appearance.fontWeightIcons
              font.variableAxes: appearance.fontVariableAxesIcons
              font.pixelSize: appearance.iconSizeMd
            }

            Text {
              objectName: "submitLabel"
              anchors.verticalCenter: parent.verticalCenter
              text: root.verifying ? "VERIFYING…" : "UNLOCK"
              renderType: Text.NativeRendering
              font.family: appearance.uiFont
              font.weight: appearance.fontWeightUi
              font.variableAxes: appearance.fontVariableAxesUi
              font.pixelSize: appearance.fontSizeBody
              font.letterSpacing: appearance.letterSpacingCaption
              color: submitButton.armed ? appearance.accentText : appearance.textMuted
            }
          }

          // Hover from a handler, not the MouseArea: a disabled MouseArea
          // receives no mouse events, so the button would lose its hover state
          // at exactly the moment it is inert.
          HoverHandler {
            id: submitHover
          }

          MouseArea {
            id: submitMouse
            anchors.fill: parent
            enabled: submitButton.armed
            cursorShape: submitButton.armed ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.attempt()
          }
        }
      }
    }
  }

  Component.onCompleted: passwordInput.forceActiveFocus()
}
