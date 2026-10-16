package com.jackwallner.hockey.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.hockey.data.DirectPurchaseOutcome
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.findActivity
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import kotlinx.coroutines.launch

enum class PlusCTAStyle { CAPSULE, BAR }

/**
 * The app's in-place conversion control: tap it and Google Play's purchase
 * sheet is next. The plan picker stays behind a quiet "See all plans" link.
 */
@Composable
fun PlusDirectCTA(
    trigger: PaywallTrigger,
    style: PlusCTAStyle = PlusCTAStyle.BAR,
    showsAllPlansLink: Boolean = true,
) {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val actions = LocalAppActions.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isPurchasing by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(trigger) {
        store.trackPaywallImpression(trigger.paywallImpressionId, oncePerSession = true)
        if (store.offeringId == null) store.fetchProducts()
    }

    val label = store.directCTALabel(trigger)
    fun buy() {
        val activity = context.findActivity() ?: return
        status = null
        isPurchasing = true
        scope.launch {
            when (val outcome = store.purchaseYearlyDirect(activity)) {
                DirectPurchaseOutcome.Unlocked -> Unit
                DirectPurchaseOutcome.Pending -> status = "Purchase pending approval. StatScout+ unlocks automatically once it's approved."
                DirectPurchaseOutcome.Cancelled -> status = "Purchase cancelled. Tap again to continue."
                is DirectPurchaseOutcome.Failed -> status = outcome.message
                DirectPurchaseOutcome.NeedsPlanPicker -> actions.openPaywall(trigger)
            }
            isPurchasing = false
        }
    }

    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Billed amount, directly above the purchase point, one type step above the
        // CTA label. Fixed height so a late price fetch never shifts the button.
        Box(Modifier.height(22.dp), contentAlignment = Alignment.Center) {
            Text(store.yearlyPlan?.priceLabel ?: " ", style = RinkType.priceLead, color = RinkPalette.ink, textAlign = TextAlign.Center, maxLines = 1)
        }
        val a11y = label
        when (style) {
            PlusCTAStyle.CAPSULE -> Row(
                Modifier.height(42.dp).clip(CircleShape).background(RinkPalette.turf)
                    .clickable(enabled = !isPurchasing) { buy() }.semantics { contentDescription = a11y }.testTag("plusCTA")
                    .padding(horizontal = 22.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isPurchasing) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                else {
                    SfIcon("crown.fill", 13.dp, Color.White)
                    Text(label, style = RinkType.bodyBold, color = Color.White)
                }
            }
            PlusCTAStyle.BAR -> Box(
                Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(12.dp)).background(RinkPalette.turf)
                    .clickable(enabled = !isPurchasing) { buy() }.semantics { contentDescription = a11y }.testTag("plusCTA"),
                contentAlignment = Alignment.Center,
            ) {
                if (isPurchasing) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                else Text(label, style = RinkType.bodyBold, color = Color.White, textAlign = TextAlign.Center, maxLines = 1)
            }
        }
        val disclosure = store.yearlyCTADisclosureText ?: store.paywallBlurSubtext
        disclosure?.let {
            Text(it, style = RinkType.micro.copy(letterSpacing = 0.3.sp), color = RinkPalette.inkTertiary, textAlign = TextAlign.Center)
        }
        status?.let { Text(it, style = RinkType.micro, color = RinkPalette.turf, textAlign = TextAlign.Center) }
        if (showsAllPlansLink) {
            TextAction("See all plans", RinkType.micro.copy(letterSpacing = 0.3.sp), RinkPalette.inkSecondary, { actions.openPaywall(trigger) })
        }
    }
}

/**
 * The unlock affordance over a blurred teaser: fades the preview into the card, then the CTA.
 * [compact] trims the fade band and bottom margin for a card on a short screen.
 */
@Composable
fun BlurGateUnlock(headline: String, trigger: PaywallTrigger, modifier: Modifier = Modifier, compact: Boolean = false) {
    Column(
        modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Transparent, RinkPalette.surface.copy(alpha = 0.95f), RinkPalette.surface)))
            .padding(start = 20.dp, end = 20.dp, top = if (compact) 12.dp else 52.dp, bottom = if (compact) 2.dp else 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(headline, style = RinkType.smallBold, color = RinkPalette.ink, textAlign = TextAlign.Center)
        PlusDirectCTA(trigger, PlusCTAStyle.CAPSULE)
    }
}

/** "What do these stats mean?": the glossary, from the bottom of any stat-heavy page. */
@Composable
fun StatGlossaryLink() {
    val navigator = LocalNavigator.current
    Row(
        Modifier.fillMaxWidth().rinkCard().clickable { navigator.push(Route.Glossary) }
            .semantics { contentDescription = "Stat glossary. Definitions for every stat in StatScout" }
            .padding(RinkGeo.padCard),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfIcon("info.circle", 16.dp, RinkPalette.turf)
        Text("What do these stats mean?", style = RinkType.small, color = RinkPalette.turf, modifier = Modifier.weight(1f))
        SfIcon("chevron.right", 16.dp, RinkPalette.inkTertiary)
    }
}

@Composable
fun Hairline(modifier: Modifier = Modifier, color: Color = RinkPalette.divider) {
    Spacer(modifier.fillMaxWidth().height(RinkGeo.hairline).background(color))
}
