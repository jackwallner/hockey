package com.jackwallner.hockey.model

import java.text.Normalizer

private val COMBINING_MARKS = Regex("\\p{Mn}+")

private fun folded(text: String): String =
    COMBINING_MARKS.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()

/** Case- and accent-blind search, so "stutzle" finds "Stützle" and "lafreniere" finds "Lafrenière". */
fun String.searchMatches(query: String): Boolean = folded(this).contains(folded(query))
