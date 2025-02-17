using System;

namespace STROM.ATOM.TOOL.Common.Extensions.StringExtensions
{
    public static class StringExtensions
    {
        /// <summary>
        /// Limits the string to a maximum number of characters.
        /// If the string is longer than <paramref name="maxLength"/>, it returns a substring of the first <paramref name="maxLength"/> characters.
        /// Otherwise, it returns the original string.
        /// </summary>
        /// <param name="input">The input string.</param>
        /// <param name="maxLength">The maximum number of characters to allow.</param>
        /// <returns>A string limited to <paramref name="maxLength"/> characters.</returns>
        /// <exception cref="ArgumentNullException">Thrown if <paramref name="input"/> is null.</exception>
        /// <exception cref="ArgumentOutOfRangeException">Thrown if <paramref name="maxLength"/> is negative.</exception>
        public static string Limit(this string input, int maxLength)
        {
            if (input == null)
                throw new ArgumentNullException(nameof(input));
            if (maxLength < 0)
                throw new ArgumentOutOfRangeException(nameof(maxLength), "maxLength must be non-negative.");

            return input.Length <= maxLength ? input : input.Substring(0, maxLength);
        }

        public static string PadLimit(this string input, int maxLength)
        {
            input = input.PadRight(maxLength);
            input = input.Limit(maxLength);
            return input;
        }
    }
}
