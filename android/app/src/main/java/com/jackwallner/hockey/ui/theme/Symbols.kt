package com.jackwallner.hockey.ui.theme

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowCircleDown
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Functions
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Leaderboard
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.ManageSearch
import androidx.compose.material.icons.filled.MonetizationOn
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.PendingActions
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.RemoveModerator
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.SouthEast
import androidx.compose.material.icons.filled.SportsHockey
import androidx.compose.material.icons.filled.Stadium
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.SwapHorizontalCircle
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** The crown StatScout+ wears everywhere; Material has none, so it is drawn here. */
val CrownIcon: ImageVector by lazy {
    ImageVector.Builder("Crown", 24.dp, 24.dp, 24f, 24f).apply {
        path(fill = SolidColor(Color.Black)) {
            moveTo(3f, 7.5f)
            lineTo(7.5f, 11.5f)
            lineTo(12f, 4.5f)
            lineTo(16.5f, 11.5f)
            lineTo(21f, 7.5f)
            lineTo(19.5f, 18f)
            lineTo(4.5f, 18f)
            close()
            moveTo(4.5f, 19.5f)
            lineTo(19.5f, 19.5f)
            lineTo(19.5f, 21f)
            lineTo(4.5f, 21f)
            close()
        }
    }.build()
}

/** iOS SF Symbol names to their closest Material equivalents, so ported views keep the iOS names. */
fun sf(name: String): ImageVector = when (name) {
    "crown.fill" -> CrownIcon
    "arrow.clockwise" -> Icons.Filled.Refresh
    "arrow.counterclockwise.circle.fill" -> Icons.Filled.Replay
    "arrow.down" -> Icons.Filled.ArrowDownward
    "arrow.up" -> Icons.Filled.ArrowUpward
    "arrow.down.circle.fill" -> Icons.Filled.ArrowCircleDown
    "arrow.down.right" -> Icons.Filled.SouthEast
    "arrow.up.right" -> Icons.Filled.NorthEast
    "arrow.left.arrow.right" -> Icons.Filled.SwapHoriz
    "arrow.left.arrow.right.circle.fill" -> Icons.Filled.SwapHorizontalCircle
    "arrow.right" -> Icons.AutoMirrored.Filled.ArrowForward
    "arrow.triangle.2.circlepath" -> Icons.Filled.Sync
    "arrow.up.arrow.down" -> Icons.Filled.SwapVert
    "binoculars.fill" -> Icons.Filled.ManageSearch
    "bolt.fill" -> Icons.Filled.Bolt
    "calendar" -> Icons.Filled.CalendarToday
    "calendar.badge.clock" -> Icons.Filled.CalendarMonth
    "calendar.badge.exclamationmark" -> Icons.Filled.EventBusy
    "chart.bar", "chart.bar.fill" -> Icons.Filled.BarChart
    "chart.bar.xaxis" -> Icons.Filled.Leaderboard
    "chart.line.flattrend.xyaxis" -> Icons.AutoMirrored.Filled.ShowChart
    "chart.line.uptrend.xyaxis" -> Icons.AutoMirrored.Filled.TrendingUp
    "chart.xyaxis.line" -> Icons.Filled.Timeline
    "checkmark" -> Icons.Filled.Check
    "checkmark.circle.fill" -> Icons.Filled.CheckCircle
    "checkmark.shield.fill" -> Icons.Filled.VerifiedUser
    "chevron.down" -> Icons.Filled.KeyboardArrowDown
    "chevron.right" -> Icons.Filled.ChevronRight
    "circle.lefthalf.filled" -> Icons.Filled.Contrast
    "clock.arrow.circlepath" -> Icons.Filled.History
    "clock.badge.exclamationmark" -> Icons.Filled.PendingActions
    "cloud.sun.fill" -> Icons.Filled.WbSunny
    "dollarsign.circle", "dollarsign.circle.fill" -> Icons.Filled.MonetizationOn
    "envelope.fill" -> Icons.Filled.Email
    "exclamationmark.triangle", "exclamationmark.triangle.fill" -> Icons.Filled.Warning
    "flame.fill" -> Icons.Filled.LocalFireDepartment
    "hockey.puck.fill", "hockey.puck.fill" -> Icons.Filled.SportsHockey
    "gearshape" -> Icons.Outlined.Settings
    "info.circle" -> Icons.Outlined.Info
    "line.3.horizontal.decrease.circle" -> Icons.Filled.FilterList
    "list.bullet.rectangle" -> Icons.AutoMirrored.Filled.ListAlt
    "lock.fill" -> Icons.Filled.Lock
    "magnifyingglass" -> Icons.Filled.Search
    "minus" -> Icons.Filled.Remove
    "person.2.fill" -> Icons.Filled.People
    "person.2.slash", "person.slash" -> Icons.Filled.PersonOff
    "person.fill" -> Icons.Filled.Person
    "person.text.rectangle" -> Icons.Filled.Badge
    "plus" -> Icons.Filled.Add
    "plus.circle" -> Icons.Outlined.AddCircleOutline
    "shield.lefthalf.filled" -> Icons.Filled.Shield
    "shield.lefthalf.filled.slash" -> Icons.Filled.RemoveModerator
    "slider.horizontal.3" -> Icons.Filled.Tune
    "snowflake" -> Icons.Filled.AcUnit
    "sportscourt.fill" -> Icons.Filled.Stadium
    "square.and.pencil" -> Icons.Filled.Edit
    "star" -> Icons.Outlined.StarOutline
    "star.fill" -> Icons.Filled.Star
    "star.slash" -> Icons.Outlined.StarOutline
    "sum" -> Icons.Filled.Functions
    "text.book.closed.fill" -> Icons.AutoMirrored.Filled.MenuBook
    "trophy.fill" -> Icons.Filled.EmojiEvents
    "wifi.exclamationmark", "wifi.slash" -> Icons.Filled.WifiOff
    "xmark.circle.fill" -> Icons.Filled.Cancel
    else -> Icons.Outlined.Info
}
