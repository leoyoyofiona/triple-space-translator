namespace TripleSpaceTranslator.Win.Services.Translation;

public interface ITranslator
{
    Task<string> TranslateAsync(string text, string sourceLang, string targetLang, CancellationToken cancellationToken);
}
