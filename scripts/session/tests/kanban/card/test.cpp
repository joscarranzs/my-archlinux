// Headless test for the kanban card gesture layer: QTest drives the real
// component through a QQuickView with the offscreen platform.
//
// Run: ./run.sh
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QTest>

class CardTest : public QObject
{
    Q_OBJECT

private:
    QQuickView view;
    QQuickItem *root = nullptr;
    QQuickItem *card = nullptr;

    int iv(const char *name) const { return root->property(name).toInt(); }
    QString sv(const char *name) const { return root->property(name).toString(); }

    void typeText(const QString &text)
    {
        // QTest has no keyClicks() overload for a QWindow: send the characters.
        for (const QChar ch : text)
            QTest::keyClick(&view, ch.unicode());
    }

    QPoint bodyPoint() const
    {
        // Bottom band of the plaque: outside the label, which is the half a
        // user actually grabs. This is where the old build was dead.
        const int py = int(card->y() + card->height() - 6);
        return QPoint(int(card->x() + card->width() / 2), py);
    }

private slots:
    void initTestCase()
    {
        view.setSource(QUrl::fromLocalFile(QStringLiteral(QML_PATH)));
        QCOMPARE(view.status(), QQuickView::Ready);
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));
        root = view.rootObject();
        QVERIFY(root);
        card = root->findChild<QQuickItem *>("card");
        QVERIFY(card);
    }

    void holdStartsDrag()
    {
        const int before = iv("dragStarts");
        QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, bodyPoint());
        QTest::qWait(300);
        QCOMPARE(iv("dragStarts"), before + 1);
        QVERIFY(card->property("dragging").toBool());
        QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, bodyPoint());
        QCOMPARE(iv("dragFinishes"), 1);
        QVERIFY(!card->property("dragging").toBool());
    }

    void dragReportsPosition()
    {
        const QPoint from = bodyPoint();
        QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, from);
        QTest::qWait(300);
        QTest::mouseMove(&view, from + QPoint(60, 0));
        QTest::mouseMove(&view, from + QPoint(120, 10));
        QVERIFY2(iv("dragUpdates") >= 2, "the ghost never got a position");
        QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, from + QPoint(120, 10));
    }

    void hoverDoesNotDrag()
    {
        // No button, no gesture: hover moves must never arm a drag.
        const int before = iv("dragStarts");
        QTest::mouseMove(&view, QPoint(60, 40));
        QTest::mouseMove(&view, QPoint(200, 50));
        QTest::qWait(250);
        QCOMPARE(iv("dragStarts"), before);
        QVERIFY(!card->property("dragging").toBool());
    }

    void sideMoveStartsDrag()
    {
        // The way a hand actually drags: press and pull sideways at once.
        const int before = iv("dragStarts");
        const QPoint from = bodyPoint();
        QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, from);
        QTest::mouseMove(&view, from + QPoint(20, 0));
        QTest::mouseMove(&view, from + QPoint(45, 2));
        QCOMPARE(iv("dragStarts"), before + 1);
        QVERIFY2(iv("dragUpdates") >= 1, "a sideways pull gave no drag position");
        QVERIFY(card->property("dragging").toBool());
        QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, from + QPoint(45, 2));
        QVERIFY(!card->property("dragging").toBool());
    }

    void verticalSwipeDoesNotDrag()
    {
        const int before = iv("dragStarts");
        const QPoint from = bodyPoint();
        QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, from);
        QTest::mouseMove(&view, from + QPoint(2, -20));
        QTest::mouseMove(&view, from + QPoint(3, -30));
        QTest::qWait(300);
        QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, from + QPoint(3, -30));
        QCOMPARE(iv("dragStarts"), before);
    }

    void singleClickDoesNotDrag()
    {
        const int before = iv("dragStarts");
        QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, bodyPoint());
        QCOMPARE(iv("dragStarts"), before);
    }

    void rightClickAsksForDeletion()
    {
        // The trash badge is gone: it cluttered a card for a gesture used once
        // in a session. Right click on the body is the ask now, and it must only
        // ask -- the panel's dialog is what can archive.
        QVERIFY2(!card->findChild<QQuickItem *>("kanban-card-delete"),
                 "the delete badge still exists in the card");
        root->setProperty("lastDelete", QString());
        QTest::mouseClick(&view, Qt::RightButton, Qt::NoModifier, bodyPoint());
        QCOMPARE(sv("lastDelete"), QStringLiteral("t1"));
    }

    void leftClickDoesNotAskToDelete()
    {
        // The same body click with the other button must stay a plain click:
        // selection and drag live there.
        root->setProperty("lastDelete", QString());
        QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, bodyPoint());
        QCOMPARE(sv("lastDelete"), QString());
    }

    void rightClickDoesNotPreview()
    {
        // A right double click is two archive asks, never a preview.
        root->setProperty("lastPreview", QString());
        QTest::mouseDClick(&view, Qt::RightButton, Qt::NoModifier, bodyPoint());
        QCOMPARE(sv("lastPreview"), QString());
        QCOMPARE(sv("lastDelete"), QStringLiteral("t1"));
    }

    void leftClickPreviews()
    {
        // The preview is the card's single gesture, and it fires on release: the
        // arbitration that used to wait for a second click existed only because
        // a double click could start an edit here.
        root->setProperty("lastPreview", QString());
        QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, bodyPoint());
        QCOMPARE(sv("lastPreview"), QStringLiteral("t1"));
    }

    void doubleClickDoesNotEdit()
    {
        // Editing moved to the sheet. The card must keep answering with one
        // preview, and it must not have grown an editor back.
        QVERIFY2(!card->findChild<QQuickItem *>("editField"), "the card still owns an edit field");
        root->setProperty("lastPreview", QString());
        QTest::mouseDClick(&view, Qt::LeftButton, Qt::NoModifier, bodyPoint());
        QTest::qWait(300);
        QCOMPARE(sv("lastPreview"), QStringLiteral("t1"));
    }

    void dragReleaseDoesNotPreview()
    {
        // The drop ends the drag on release, and Qt composes the click after
        // that, so `dragging` is already false when the card decides. Asking it
        // opened the sheet on every drop; the gesture has to remember that it
        // moved. Hold path first, then the sideways one.
        for (int attempt = 0; attempt < 2; ++attempt) {
            const int before = iv("dragStarts");
            root->setProperty("lastPreview", QString());
            const QPoint from = bodyPoint();
            QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, from);
            if (attempt == 0) {
                QTest::qWait(300);
            } else {
                QTest::mouseMove(&view, from + QPoint(20, 0));
                QTest::mouseMove(&view, from + QPoint(45, 2));
            }
            QCOMPARE(iv("dragStarts"), before + 1);
            QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier,
                                attempt == 0 ? from : from + QPoint(45, 2));
            QCOMPARE(sv("lastPreview"), QString());
            QVERIFY(!card->property("dragging").toBool());
        }
    }

    void clickAfterDragStillPreviews()
    {
        // The flag is per press: the next plain click must open the sheet again,
        // not stay muted by the drag that came before it.
        const QPoint from = bodyPoint();
        QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, from);
        QTest::qWait(300);
        QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, from);
        root->setProperty("lastPreview", QString());
        QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, from);
        QCOMPARE(sv("lastPreview"), QStringLiteral("t1"));
    }
};

QTEST_MAIN(CardTest)
#include "test.moc"
