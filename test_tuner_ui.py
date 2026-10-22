import os
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtCore import QObject, Property, QUrl, Slot, QPoint, Qt
from PySide6.QtQuick import QQuickView
from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest
import pytest

ROOT = Path(__file__).resolve().parent


class Host(QObject):
    def __init__(self):
        super().__init__()
        self.changes = []

    @Property(str, constant=True)
    def name(self):
        return 'Arial'

    @Slot(str, str, bool)
    def set_port_broadcast(self, *args):
        pass

    @Slot(str, str, float)
    def ui_knob_change(self, effect, control, value):
        self.changes.append((effect, control, value))

    @Slot(str, result=int)
    def frameRevision(self, effect):
        return 0

    @Slot(str, result=str)
    def takeFramesJson(self, effect):
        return '[]'

    @Slot(str)
    def clearEffect(self, effect):
        pass

    @Slot(str)
    def notePainted(self, effect):
        pass

    @Slot(float)
    def noteQmlGc(self, value):
        pass


@pytest.fixture(scope='module')
def ui():
    app = QGuiApplication.instance() or QGuiApplication([])
    view = QQuickView()
    host = Host()
    context = view.rootContext()
    for name in ['mainFont', 'knobs', 'scopeFrames']:
        context.setContextProperty(name, host)
    context.setContextProperty('currentEffects', {'scope1': {'controls': {}}})
    errors = []
    view.engine().warnings.connect(lambda warnings: errors.extend(w.toString() for w in warnings))
    view.setSource(QUrl.fromLocalFile(str(ROOT / 'source/polyeffects-src/digit_ui/qml/Polyscope.qml')))
    assert view.status() == QQuickView.Ready, [e.toString() for e in view.errors()]
    view.show()
    QTest.qWait(80)
    root = view.rootObject()
    root.setProperty('uiPage', 'tuner')
    root.setProperty('pluginFreqs', [440.0, 261.625565, 329.627557, 523.251131])
    yield view, root, host, errors
    view.setSource(QUrl())
    app.processEvents()
    view.close()
    view.deleteLater()
    app.processEvents()


def click(view, x, y):
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(x, y))
    QTest.qWait(20)


def test_tuner_controls_and_readings(ui):
    view, root, host, errors = ui
    assert root.tunerNoteName(440.0) == 'A4'
    assert root.tunerCents(440.0) == 0
    assert root.tunerNoteName(261.625565) == 'C4'
    assert abs(root.tunerCents(440 * 2**(25/1200)) - 25) < 1e-8
    assert abs(root.tunerTargetHz(441.0) - 440) < 1e-8
    for hz in [0., 15., 8001., float('nan')]:
        assert not root.tunerValid(hz)
    click(view, 1020, 48)
    assert root.property('tunerA4') == 441.0
    click(view, 760, 48)
    assert root.property('tunerA4') == 440.0
    root.stepTunerA4(1000.)
    assert root.property('tunerA4') == 480.0
    root.stepTunerA4(-1000.)
    assert root.property('tunerA4') == 400.0
    QTest.mouseDClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(880, 48))
    QTest.qWait(20)
    assert root.property('tunerA4') == 440.0
    for c in range(4):
        click(view, 1160, 126 + c * 129)
        assert root.property('tunerChannel') == c
    click(view, 100, 48)
    assert root.property('uiPage') == 'main'
    root.setProperty('uiPage', 'tuner')
    root.setProperty('freeze', True)
    click(view, 530, 555)
    assert host.changes[-1] == ('scope1', 'freeze', 0.0)
    root.setProperty('freeze', False)
    assert not errors, errors


def test_frozen_and_live_screens(ui):
    view, root, host, errors = ui
    root.setProperty('uiPage', 'tuner')
    root.setProperty('tunerChannel', 0)
    root.setProperty('pluginFreqs', [440., 261.625565, 329.627557, 523.251131])
    out = ROOT / 'validation'
    out.mkdir(exist_ok=True)
    for name, freeze, freqs in [('tuner-live', False, [440., 261.625565, 329.627557, 523.251131]),
                                ('tuner-frozen', True, [440., 261.625565, 329.627557, 523.251131]),
                                ('tuner-no-signal', False, [0., 0., 0., 0.]),
                                ('tuner-out-of-tune', False, [445., 261.625565, 329.627557, 523.251131])]:
        root.setProperty('freeze', freeze)
        root.setProperty('pluginFreqs', freqs)
        QTest.qWait(80)
        assert view.grabWindow().save(str(out / (name + '.png')))
    assert not errors, errors
