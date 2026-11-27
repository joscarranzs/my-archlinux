// Headless test for the lane's dismiss gesture: QTest drives the real
// KanbanSection through a QQuickView with the offscreen platform.
//
// The rule under test is the one a screenshot cannot prove: a Flickable takes
// every press inside it, so the lane has to hand "click beside a task" up to the
// panel itself -- and it must not steal the click that belongs to a card.
//
// Run: ./run.sh
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QTest>

class SectionTest : public QObject
{
    Q_OBJECT

private:
    QQuickView view;
    QQuickItem *root = nullptr;
    QQuickItem *section = nullptr;

    int dismisses() const { return root->property("dismisses").toInt(); }
    QString lastPreview() const { return root->property("lastPreview").toString(); }

    QPoint centre(QQuickItem *item) const
    {
        const QPointF p = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
        return p.toPoint();
    }

    // The delegates are created by the Repeater: their QObject parent is the
    // engine, not the lane, so findChildren() never sees them -- only the visual
    // tree does. Walk that instead, in model order, and match on the objectName.
    void collectCards(QQuickItem *item, QList<QQuickItem *> &out) const
    {
        if (item->objectName().startsWith(QStringLiteral("kanban-card-")))
            out.append(item);
        const auto kids = item->childItems();
        for (QQuickItem *kid : kids)
            collectCards(kid, out);
    }

    QQuickItem *cardAt(int index) const
    {
        QList<QQuickItem *> cards;
        collectCards(section, cards);
        return index >= 0 && index < cards.size() ? cards.at(index) : nullptr;
    }

private slots:
    void initTestCase()
    {
        view.setSource(QUrl::fromLocalFile(QStringLiteral(QML_PATH)));
        QCOMPARE(view.status(), QQuickView::Ready);
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));
        QTest::qWait(50);
        root = view.rootObject();
        QVERIFY(root);
        section = root->findChild<QQuickItem *>("section");
        QVERIFY(section);
    }

    void laneCarriesADismissArea()
    {
        // One per lane, and it has to be inside the lane: the panel's own
        // catcher sits below the Flickable and never sees these presses.
        auto *area = section->findChild<QQuickItem *>("section-dismiss");
        QVERIFY(area);
        QVERIFY(area->width() > 0 && area->height() > 0);
    }

    void emptyLaneClosesTheSheet()
    {
        auto *area = section->findChild<QQuickItem *>("section-dismiss");
        QVERIFY(area);
        const int before = dismisses();
        QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, centre(area));
        QCOMPARE(dismisses(), before + 1);
    }

    void cardClickIsNotADismiss()
    {
        // The dismiss area sits under the cards: a press on one belongs to the
        // card, which asks for the preview. If the lane swallowed it, the sheet
        // would close instead of moving to the task that was clicked.
        auto *card = cardAt(1);
        QVERIFY(card);
        const int before = dismisses();
        root->setProperty("lastPreview", QString());
        QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, centre(card));
        QCOMPARE(dismisses(), before);
        QCOMPARE(lastPreview(), QStringLiteral("t2"));
    }

    void headerIsNotTheDismissArea()
    {
        // The header band is not a Flickable and carries no handler of its own;
        // the panel's catcher answers there, so the lane must stay silent and
        // let the press through. A lane that dismissed from the header would
        // also dismiss on the count and on the drop feedback.
        const int before = dismisses();
        const QPoint header(int(section->width() / 2), 16);
        QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, header);
        QCOMPARE(dismisses(), before);
    }
};

QTEST_MAIN(SectionTest)
#include "test.moc"
