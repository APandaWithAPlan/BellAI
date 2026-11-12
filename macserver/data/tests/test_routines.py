import importlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi import HTTPException
from pydantic import ValidationError
from routines import Routine, create_routine, list_routines


class RoutineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.database = patch('storage.DB_PATH', str(Path(self.directory.name) / 'test.db'))
        self.database.start()
        self.addCleanup(self.database.stop)
        self.server = importlib.reload(importlib.import_module('bell_data_server'))
        self.payload = dict(id=str(uuid4()), name=' Morning ', time='07:30',
                            timezone='America/Chicago', actions=[' Turn on lights ', 'Read agenda'])

    def test_validation(self):
        routine = Routine(**self.payload)
        self.assertEqual(routine.name, 'Morning')
        self.assertEqual(routine.actions[0], 'Turn on lights')
        for change in ({'name': ' '}, {'time': '24:00'}, {'actions': []},
                       {'actions': [' ']}, {'actions': ['x' * 501]},
                       {'timezone': 'Invalid/Zone'}):
            with self.subTest(change=change), self.assertRaises(ValidationError):
                Routine(**(self.payload | change))

    def test_persistence_retry_and_task_isolation(self):
        self.assertEqual(list_routines(), {'routines': []})
        tasks = {'tasks': [{'title': 'Keep this task'}]}
        self.server.put_data(self.server.Save(data=tasks))
        routine = Routine(**self.payload)
        expected = routine.model_dump(mode='json')
        self.assertEqual(create_routine(routine), expected)
        self.assertEqual(create_routine(routine), expected)
        self.assertEqual(list_routines(), {'routines': [expected]})
        self.assertEqual(self.server.get_data(), {'data': tasks})
        self.server.put_data(self.server.Save(data={'tasks': []}))
        self.assertEqual(list_routines(), {'routines': [expected]})
        with self.assertRaises(HTTPException) as error:
            create_routine(Routine(**(self.payload | {'name': 'Changed'})))
        self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(list_routines(), {'routines': [expected]})

    def test_parameterized_text_and_order(self):
        late = Routine(**(self.payload | {'name': "Evening'); DROP TABLE routines;--", 'time': '20:00'}))
        early = Routine(**(self.payload | {'id': str(uuid4()), 'time': '06:00'}))
        create_routine(late)
        create_routine(early)
        saved = list_routines()['routines']
        self.assertEqual([row['time'] for row in saved], ['06:00', '20:00'])
        self.assertEqual(saved[1]['name'], late.name)


if __name__ == '__main__':
    unittest.main()
