import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import QtQuick.VirtualKeyboard
import SddmComponents 2.0

// macOS-style login screen. A random wallpaper from ./backgrounds on every start
// (synced from ~/Pictures/Logging), captioned like Windows Spotlight.
Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "black"

    readonly property string fontFamily: config.Font || "Inter"
    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    property bool failed: false
    property string wallpaper: ""
    property bool showPassword: false
    property bool keyboardOn: false // on-screen keyboard, only when asked for

    // ---------- Wallpaper ----------
    FolderListModel {
        id: walls
        folder: Qt.resolvedUrl("backgrounds")
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready && count > 0 && !root.wallpaper)
            root.wallpaper = get(Math.floor(Math.random() * count), "fileUrl")
    }
    // "Title — Location.jpg" -> caption
    readonly property var caption: {
        const name = decodeURIComponent(wallpaper.toString().split("/").pop()).replace(/\.[^.]+$/, "");
        const parts = name.split(" — ");
        return { title: parts[0], place: parts.slice(1).join(" — ") };
    }

    Image {
        id: wall
        anchors.fill: parent
        source: root.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
    }

    // Blurred copy, sampled by the glass controls
    MultiEffect {
        id: blurred
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        visible: true
        opacity: 0 // rendered for ShaderEffectSource, not shown
        layer.enabled: true
    }

    // Soft vignette so white text stays readable on bright photos
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // ---------- Clock ----------
    Timer { interval: 1000; running: true; repeat: true; onTriggered: now = new Date() }
    property date now: new Date()

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.07 }
        spacing: -6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd d MMMM")
            color: Qt.rgba(1, 1, 1, 0.88)
            font { family: root.fontFamily; pixelSize: 26; weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            color: Qt.rgba(1, 1, 1, 0.9)
            font { family: root.fontFamily; pixelSize: 132; weight: Font.Bold; letterSpacing: -3 }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.25; shadowBlur: 0.6; shadowVerticalOffset: 2 }
        }
    }

    // ---------- User + password ----------
    Column {
        id: login
        width: 340 // wide enough for the keyboard button beside the field (the shadow layer clips)
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.35; shadowBlur: 0.5; shadowVerticalOffset: 1 }
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        // Moves up above the on-screen keyboard when it's open
        anchors.bottomMargin: root.keyboardOn ? keyboard.height + 60 : parent.height * 0.12
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        spacing: 14

        // Avatar: the user's face icon if SDDM can read it, else initials on glass
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76; height: 76
            Glass { anchors.fill: parent; blurSource: blurred; tint: Qt.rgba(0.08, 0.08, 0.10, 0.30) }
            Text {
                anchors.centerIn: parent
                visible: face.status !== Image.Ready
                text: userName.text.charAt(0).toUpperCase()
                color: "white"
                font { family: root.fontFamily; pixelSize: 32; weight: Font.DemiBold }
            }
            Image {
                id: face
                anchors.fill: parent
                source: userRepeater.count > 0 ? (userRepeater.itemAt(root.userIndex)?.icon ?? "") : ""
                visible: false
                fillMode: Image.PreserveAspectCrop
            }
            Rectangle { id: faceMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                visible: face.status === Image.Ready
                source: face
                maskEnabled: true
                maskSource: faceMask
            }
        }

        // Hidden repeater to read userModel roles by index
        Repeater {
            id: userRepeater
            model: userModel
            delegate: Item {
                required property string name
                required property string realName
                required property string icon
                visible: false
            }
        }

        Text {
            id: userName
            anchors.horizontalCenter: parent.horizontalCenter
            // .count makes this re-evaluate once the model is populated (itemAt() doesn't notify)
            readonly property Item u: userRepeater.count > 0 ? userRepeater.itemAt(root.userIndex) : null
            text: u ? (u.realName || u.name) : ""
            color: "white"
            font { family: root.fontFamily; pixelSize: 17; weight: Font.DemiBold }
            MouseArea { // several accounts: click the name to switch
                anchors.fill: parent
                enabled: userModel.count > 1
                cursorShape: Qt.PointingHandCursor
                onClicked: root.userIndex = (root.userIndex + 1) % userModel.count
            }
        }

        Item {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 236; height: 36

            Glass { anchors.fill: parent; blurSource: blurred; tint: Qt.rgba(0.08, 0.08, 0.10, password.activeFocus ? 0.36 : 0.28) }

            TextInput {
                id: password
                anchors { fill: parent; leftMargin: 16; rightMargin: 68 }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                passwordCharacter: "●"
                color: "white"
                font { family: root.fontFamily; pixelSize: 14; letterSpacing: 1 }
                selectionColor: Qt.rgba(1, 1, 1, 0.3)
                clip: true
                focus: true
                onTextEdited: root.failed = false
                onAccepted: root.doLogin()
                Keys.onEscapePressed: text = ""

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !password.text
                    text: "Enter Password"
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font { family: root.fontFamily; pixelSize: 14 }
                }
            }

            // Eye: show / hide the password
            Text {
                anchors { right: parent.right; rightMargin: 38; verticalCenter: parent.verticalCenter }
                text: root.showPassword ? "\u{f0209}" : "\u{f0208}" // eye-off / eye
                color: eyeMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.7)
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
                opacity: password.text ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                MouseArea {
                    id: eyeMouse
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.showPassword = !root.showPassword; password.forceActiveFocus(); }
                }
            }

            // Keyboard button, just right of the field: toggles the on-screen keyboard
            Item {
                x: parent.width + 10
                width: 36; height: 36
                Glass {
                    anchors.fill: parent
                    blurSource: blurred
                    tint: root.keyboardOn ? Qt.rgba(1, 1, 1, 0.30) : kbdMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0.08, 0.08, 0.10, 0.28)
                }
                Text {
                    anchors.centerIn: parent
                    text: "\u{f030c}" // keyboard
                    color: "white"
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 17 }
                }
                MouseArea {
                    id: kbdMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.keyboardOn = !root.keyboardOn;
                        password.forceActiveFocus();
                        if (root.keyboardOn) Qt.inputMethod.show();
                    }
                }
            }

            // Arrow button, appears once something is typed
            Rectangle {
                anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                width: 26; height: 26; radius: 13
                color: arrowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(1, 1, 1, 0.28)
                opacity: password.text ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1
                    text: "→"
                    color: "white"
                    font { family: root.fontFamily; pixelSize: 15; weight: Font.Bold }
                }
                MouseArea { id: arrowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.doLogin() }
            }

            // macOS shake on a wrong password
            SequentialAnimation {
                id: shake
                loops: 1
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -14; duration: 50 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 12; duration: 70 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -8; duration: 70 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 5; duration: 70 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 0; duration: 60 }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.failed ? "Incorrect password" : keyboard.capsLock ? "Caps Lock is on" : " "
            color: root.failed ? "#ffb4ab" : Qt.rgba(1, 1, 1, 0.7)
            font { family: root.fontFamily; pixelSize: 12; weight: Font.Medium }
        }
    }

    function doLogin() {
        if (!password.text) return;
        sddm.login(userRepeater.itemAt(root.userIndex).name, password.text, root.sessionIndex);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.failed = true;
            password.text = "";
            password.forceActiveFocus();
            shake.start();
        }
    }

    // ---------- Bottom-left: about this picture ----------
    Column {
        anchors { left: parent.left; bottom: parent.bottom; margins: 28 }
        spacing: 2
        visible: root.wallpaper !== ""
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.5; shadowBlur: 0.5; shadowVerticalOffset: 1 }
        Text {
            text: root.caption.title
            color: "white"
            font { family: root.fontFamily; pixelSize: 15; weight: Font.DemiBold }
        }
        Text {
            text: root.caption.place
            color: Qt.rgba(1, 1, 1, 0.72)
            font { family: root.fontFamily; pixelSize: 12 }
        }
    }

    // ---------- Bottom-right: session + power ----------
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        spacing: 10

        // Session pill (click to cycle)
        Item {
            width: sessionLabel.implicitWidth + 32
            height: 36
            Glass { anchors.fill: parent; blurSource: blurred }
            Repeater {
                id: sessionRepeater
                model: sessionModel
                delegate: Item { required property string name; visible: false }
            }
            Text {
                id: sessionLabel
                anchors.centerIn: parent
                text: sessionRepeater.count > 0 ? (sessionRepeater.itemAt(root.sessionIndex)?.name ?? "") : ""
                color: "white"
                font { family: root.fontFamily; pixelSize: 13; weight: Font.Medium }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessionModel.count
            }
        }

        PowerButton { label: "Sleep"; glyph: "sleep"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
        PowerButton { label: "Restart"; glyph: "restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        PowerButton { label: "Shut Down"; glyph: "power"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }

    component PowerButton: Item {
        id: btn
        property string label
        property string glyph
        signal clicked()
        width: 36; height: 36

        Glass { anchors.fill: parent; blurSource: blurred; tint: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0.08, 0.08, 0.10, 0.28) }
        Canvas { // simple line icons
            id: icon
            anchors.centerIn: parent
            width: 16; height: 16
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.strokeStyle = "white"; c.lineWidth = 1.8; c.lineCap = "round";
                c.beginPath();
                if (btn.glyph === "power") {
                    c.arc(8, 9, 6, -Math.PI * 0.32, Math.PI * 1.32); c.moveTo(8, 1.5); c.lineTo(8, 8);
                } else if (btn.glyph === "restart") {
                    c.arc(8, 8.5, 6, -Math.PI * 0.4, Math.PI * 1.45);
                    c.moveTo(8.8, 0.8); c.lineTo(11.6, 2.9); c.lineTo(9.1, 5.2);
                } else { // crescent moon
                    c.arc(8, 8, 6.5, Math.PI * 0.35, Math.PI * 1.65);
                    c.arc(10.8, 6, 5, Math.PI * 1.15, Math.PI * 0.55, true);
                }
                c.stroke();
            }
        }
        // Label tooltip above the button
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 8 }
            text: btn.label
            color: "white"
            opacity: mouse.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            font { family: root.fontFamily; pixelSize: 12; weight: Font.Medium }
        }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
    }

    // On-screen keyboard. Declaring our own InputPanel stops Qt from popping up its
    // default one on every text focus; this one only shows after the keyboard button.
    InputPanel {
        id: keyboard
        width: Math.min(parent.width * 0.45, 860)
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.keyboardOn ? parent.height - height - 24 : parent.height
        visible: y < parent.height
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    // The keyboard's own "hide" key turns the toggle off too
    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() { if (!Qt.inputMethod.visible) root.keyboardOn = false; }
    }

    Component.onCompleted: password.forceActiveFocus()
}
