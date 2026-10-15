"""Reject partial, stale and replaying Android process-recovery evidence."""
import unittest

from scripts.test_native_process_recovery import validate_checkpoints


class ProcessRecoveryCompletion(unittest.TestCase):
    def records(self):
        return [
            {'phase': 'ready_for_stop', 'run_id': 'owned', 'pid': 100, 'submissions': 1, 'uploads': 1},
            {'phase': 'restored', 'run_id': 'owned', 'pid': 200, 'submissions': 0, 'uploads': 0,
             'draft_restored': True, 'attachment_restored': True, 'outbox_paused': True},
        ]

    def test_two_distinct_processes_restore_all_work_without_replay(self):
        validate_checkpoints(self.records(), 'owned')

    def test_partial_or_duplicate_phases_fail(self):
        records = self.records()
        for incomplete in ([], records[:1], records[1:], records[::-1], records + records[1:]):
            with self.subTest(incomplete=incomplete), self.assertRaises(ValueError):
                validate_checkpoints(incomplete, 'owned')

    def test_malformed_checkpoint_shapes_fail(self):
        for records in (None, {}, [None, None], ['ready_for_stop', 'restored']):
            with self.subTest(records=records), self.assertRaises(ValueError):
                validate_checkpoints(records, 'owned')

    def test_non_integer_counts_fail(self):
        for value in (None, True, False, '0', 0.0):
            for phase in range(2):
                for field in ('submissions', 'uploads'):
                    records = self.records()
                    records[phase][field] = value
                    with self.subTest(value=value, phase=phase, field=field), self.assertRaises(ValueError):
                        validate_checkpoints(records, 'owned')

    def test_stale_checkpoint_fails(self):
        for phase in range(2):
            records = self.records()
            records[phase]['run_id'] = 'previous'
            with self.subTest(phase=phase), self.assertRaises(ValueError):
                validate_checkpoints(records, 'owned')

    def test_owner_recreation_in_same_process_fails(self):
        records = self.records()
        records[1]['pid'] = records[0]['pid']
        with self.assertRaises(ValueError):
            validate_checkpoints(records, 'owned')

    def test_invalid_process_identity_fails(self):
        for value in (None, '', 0, -1, True):
            records = self.records()
            records[1]['pid'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_checkpoints(records, 'owned')

    def test_missing_original_submission_fails(self):
        records = self.records()
        records[0]['submissions'] = 0
        with self.assertRaises(ValueError):
            validate_checkpoints(records, 'owned')

    def test_duplicate_submit_or_upload_fails(self):
        for field in ('submissions', 'uploads'):
            records = self.records()
            records[1][field] = 1
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_checkpoints(records, 'owned')

    def test_each_missing_user_work_observation_fails(self):
        for field in ('draft_restored', 'attachment_restored', 'outbox_paused'):
            records = self.records()
            del records[1][field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_checkpoints(records, 'owned')


if __name__ == '__main__':
    unittest.main()
