package com.paisapulse.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Data stores SF Symbol names (shared with the iPhone app). Android shows the closest rounded
 * Material icon: Apple licenses SF Symbols for Apple platforms only.
 */
object Sym {
  private val map: Map<String, ImageVector> = mapOf(
    "fork.knife" to Icons.Rounded.Restaurant, "cart.fill" to Icons.Rounded.ShoppingCart, "car.fill" to Icons.Rounded.DirectionsCar,
    "fuelpump.fill" to Icons.Rounded.LocalGasStation, "tram.fill" to Icons.Rounded.Tram, "bag.fill" to Icons.Rounded.ShoppingBag,
    "doc.text.fill" to Icons.Rounded.Description, "bolt.fill" to Icons.Rounded.Bolt, "wifi" to Icons.Rounded.Wifi,
    "tv.fill" to Icons.Rounded.Tv, "house.fill" to Icons.Rounded.Home, "building.columns.fill" to Icons.Rounded.AccountBalance,
    "cross.case.fill" to Icons.Rounded.MedicalServices, "popcorn.fill" to Icons.Rounded.Movie, "repeat.circle.fill" to Icons.Rounded.Autorenew,
    "repeat" to Icons.Rounded.Repeat, "airplane" to Icons.Rounded.Flight, "graduationcap.fill" to Icons.Rounded.School,
    "gift.fill" to Icons.Rounded.CardGiftcard, "chart.line.uptrend.xyaxis" to Icons.AutoMirrored.Rounded.TrendingUp,
    "sparkles" to Icons.Rounded.AutoAwesome, "figure.2.and.child.holdinghands" to Icons.Rounded.FamilyRestroom,
    "banknote.fill" to Icons.Rounded.Payments, "laptopcomputer" to Icons.Rounded.Laptop, "percent" to Icons.Rounded.Percent,
    "arrow.uturn.backward.circle.fill" to Icons.AutoMirrored.Rounded.Undo, "indianrupeesign.circle.fill" to Icons.Rounded.CurrencyRupee,
    "indianrupeesign.circle" to Icons.Rounded.CurrencyRupee, "indianrupeesign" to Icons.Rounded.CurrencyRupee,
    "ellipsis.circle.fill" to Icons.Rounded.MoreHoriz, "ellipsis" to Icons.Rounded.MoreHoriz, "creditcard.fill" to Icons.Rounded.CreditCard,
    "wallet.bifold.fill" to Icons.Rounded.AccountBalanceWallet, "pawprint.fill" to Icons.Rounded.Pets,
    "gamecontroller.fill" to Icons.Rounded.SportsEsports, "dumbbell.fill" to Icons.Rounded.FitnessCenter,
    "cup.and.saucer.fill" to Icons.Rounded.LocalCafe, "wineglass.fill" to Icons.Rounded.WineBar, "tshirt.fill" to Icons.Rounded.Checkroom,
    "iphone" to Icons.Rounded.PhoneIphone, "wrench.and.screwdriver.fill" to Icons.Rounded.Build, "book.fill" to Icons.AutoMirrored.Rounded.MenuBook,
    "music.note" to Icons.Rounded.MusicNote, "heart.fill" to Icons.Rounded.Favorite, "leaf.fill" to Icons.Rounded.Eco,
    "scooter" to Icons.Rounded.ElectricScooter, "bicycle" to Icons.AutoMirrored.Rounded.DirectionsBike, "bus.fill" to Icons.Rounded.DirectionsBus,
    "tag.fill" to Icons.Rounded.Sell, "star.fill" to Icons.Rounded.Star, "questionmark" to Icons.Rounded.QuestionMark,
    "arrow.left.arrow.right" to Icons.Rounded.SwapHoriz, "arrow.down.left" to Icons.Rounded.SouthWest, "arrow.up.right" to Icons.Rounded.NorthEast,
    "car" to Icons.Rounded.DirectionsCar, "shield.fill" to Icons.Rounded.Shield, "camera.fill" to Icons.Rounded.PhotoCamera,
    "target" to Icons.Rounded.TrackChanges, "person.2.fill" to Icons.Rounded.Group, "person.badge.plus" to Icons.Rounded.PersonAdd,
    "calendar" to Icons.Rounded.CalendarMonth, "chart.bar.xaxis" to Icons.Rounded.BarChart, "gearshape.fill" to Icons.Rounded.Settings,
    "list.bullet.rectangle.fill" to Icons.AutoMirrored.Rounded.ReceiptLong, "magnifyingglass" to Icons.Rounded.Search,
    "plus" to Icons.Rounded.Add, "xmark" to Icons.Rounded.Close, "checkmark" to Icons.Rounded.Check, "trash" to Icons.Rounded.Delete,
    "pencil" to Icons.Rounded.Edit, "plus.square.on.square" to Icons.Rounded.ContentCopy, "square.grid.2x2.fill" to Icons.Rounded.GridView,
    "gauge.with.dots.needle.33percent" to Icons.Rounded.Speed, "gauge.with.dots.needle.67percent" to Icons.Rounded.Speed,
    "bolt" to Icons.Rounded.Bolt, "number" to Icons.Rounded.Tag, "clock.arrow.circlepath" to Icons.Rounded.History,
    "doc.text.image" to Icons.Rounded.Receipt, "storefront.fill" to Icons.Rounded.Storefront, "chart.pie.fill" to Icons.Rounded.PieChart,
    "clock.fill" to Icons.Rounded.Schedule, "circle.lefthalf.filled" to Icons.Rounded.Contrast,
    "paintpalette.fill" to Icons.Rounded.Palette, "bell.badge.fill" to Icons.Rounded.NotificationsActive, "envelope.fill" to Icons.Rounded.Mail,
    "eye" to Icons.Rounded.Visibility, "eye.slash" to Icons.Rounded.VisibilityOff, "faceid" to Icons.Rounded.Fingerprint, "eye.slash.fill" to Icons.Rounded.VisibilityOff, "externaldrive.fill" to Icons.Rounded.Backup,
    "tablecells.fill" to Icons.Rounded.TableChart, "arrow.down.circle.fill" to Icons.Rounded.Download,
    "calendar.day.timeline.left" to Icons.Rounded.DateRange, "line.3.horizontal.decrease" to Icons.Rounded.FilterList,
    "chevron.left" to Icons.AutoMirrored.Rounded.ArrowBackIos, "chevron.right" to Icons.AutoMirrored.Rounded.ArrowForwardIos,
    "archivebox" to Icons.Rounded.Archive, "lock.fill" to Icons.Rounded.Lock, "square.and.arrow.up" to Icons.Rounded.IosShare,
    "square.and.arrow.down" to Icons.Rounded.FileDownload, "delete.left" to Icons.AutoMirrored.Rounded.Backspace,
    "pause" to Icons.Rounded.Pause, "play" to Icons.Rounded.PlayArrow, "checkmark.circle" to Icons.Rounded.CheckCircleOutline,
    "checkmark.circle.fill" to Icons.Rounded.CheckCircle, "circle" to Icons.Rounded.RadioButtonUnchecked,
    "tray" to Icons.Rounded.Inbox, "message.badge.filled.fill" to Icons.Rounded.Sms, "message.badge" to Icons.Rounded.Sms, "bell.badge" to Icons.Rounded.NotificationsActive, "chevron.up" to Icons.Rounded.KeyboardArrowUp, "chevron.down" to Icons.Rounded.KeyboardArrowDown,
    "chevron.up.chevron.down" to Icons.Rounded.UnfoldMore,
    "bookmark" to Icons.Rounded.BookmarkBorder, "bookmark.fill" to Icons.Rounded.Bookmark,
    "arrow.triangle.2.circlepath" to Icons.Rounded.Sync, "arrow.up.arrow.down" to Icons.Rounded.SwapVert,
    "line.3.horizontal" to Icons.Rounded.DragHandle, "creditcard.and.123" to Icons.Rounded.Subscriptions,
    "doc.text.viewfinder" to Icons.Rounded.DocumentScanner, "photo" to Icons.Rounded.Image, "photo.on.rectangle" to Icons.Rounded.PhotoLibrary,
    "mic.fill" to Icons.Rounded.Mic, "mic" to Icons.Rounded.Mic, "stop.fill" to Icons.Rounded.Stop,
    "exclamationmark.triangle.fill" to Icons.Rounded.Warning, "arrow.uturn.backward" to Icons.AutoMirrored.Rounded.Undo,
    "doc.fill" to Icons.Rounded.InsertDriveFile, "building.columns" to Icons.Rounded.AccountBalance,
    "square.grid.2x2" to Icons.Rounded.GridView, "keyboard" to Icons.Rounded.Keyboard, "sparkles.rectangle.stack" to Icons.Rounded.AutoAwesome,
    "globe" to Icons.Rounded.Public, "photo.circle.fill" to Icons.Rounded.Image, "camera.viewfinder" to Icons.Rounded.CameraAlt,
    "banknote" to Icons.Rounded.Payments, "qrcode" to Icons.Rounded.QrCode2, "house" to Icons.Rounded.Home, "creditcard" to Icons.Rounded.CreditCard,
    "beach.umbrella.fill" to Icons.Rounded.BeachAccess, "briefcase.fill" to Icons.Rounded.BusinessCenter, "calendar.badge.clock" to Icons.Rounded.Event,
    "doc.text" to Icons.Rounded.Description, "dollarsign.arrow.circlepath" to Icons.Rounded.CurrencyExchange, "ellipsis.circle" to Icons.Rounded.MoreHoriz,
    "location.fill" to Icons.Rounded.MyLocation, "mappin.and.ellipse" to Icons.Rounded.Place, "minus.circle.fill" to Icons.Rounded.RemoveCircle,
    "party.popper.fill" to Icons.Rounded.Celebration, "plus.circle" to Icons.Rounded.AddCircleOutline, "plus.circle.fill" to Icons.Rounded.AddCircle,
    "questionmark.circle" to Icons.AutoMirrored.Rounded.HelpOutline, "tent.fill" to Icons.Rounded.Cabin, "trash.fill" to Icons.Rounded.Delete,
    "bell.fill" to Icons.Rounded.Notifications, "bell" to Icons.Rounded.NotificationsNone, "rectangle.portrait.and.arrow.right" to Icons.AutoMirrored.Rounded.Logout,
    "person.crop.circle" to Icons.Rounded.AccountCircle, "person.crop.circle.fill" to Icons.Rounded.AccountCircle,
    "person.crop.circle.badge.plus" to Icons.Rounded.PersonAdd, "checkmark.seal.fill" to Icons.Rounded.Verified, "link" to Icons.Rounded.Link,
    "icloud" to Icons.Rounded.Cloud, "cloud.fill" to Icons.Rounded.Cloud,
  )
  fun of(name: String?): ImageVector = name?.let { map[it] } ?: Icons.Rounded.Sell
}
