namespace TripleSpaceTranslator.Win.Services;

public sealed class TripleSpaceDetector
{
    private readonly Queue<long> _timestamps = new();
    private readonly TimeProvider _timeProvider;

    public TripleSpaceDetector(TimeProvider? timeProvider = null)
    {
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public bool RegisterPress(int requiredPressCount, int windowMs)
    {
        var now = _timeProvider.GetTimestamp();
        var windowTicks = _timeProvider.TimestampFrequency * windowMs / 1000;

        _timestamps.Enqueue(now);
        while (_timestamps.Count > 0 && now - _timestamps.Peek() > windowTicks)
        {
            _timestamps.Dequeue();
        }

        if (_timestamps.Count >= requiredPressCount)
        {
            _timestamps.Clear();
            return true;
        }

        return false;
    }
}
