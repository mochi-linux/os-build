import curses
import textwrap


class TUI:
    def __init__(self):
        self.stdscr = None
        self.color_bg = 0
        self.color_dialog = 0
        self.color_dialog_hl = 0
        self.color_input_bg = 0

    def start(self, stdscr):
        self.stdscr = stdscr
        curses.curs_set(0)
        curses.start_color()
        curses.use_default_colors()

        # Define color pairs (fg, bg)
        curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLUE)
        curses.init_pair(2, curses.COLOR_BLACK, curses.COLOR_WHITE)
        curses.init_pair(3, curses.COLOR_WHITE, curses.COLOR_RED)
        curses.init_pair(4, curses.COLOR_WHITE, curses.COLOR_BLACK)

        self.color_bg = curses.color_pair(1)
        self.color_dialog = curses.color_pair(2)
        self.color_dialog_hl = curses.color_pair(3)
        self.color_input_bg = curses.color_pair(4)

        self.draw_bg()

    def draw_bg(self):
        if not self.stdscr:
            return
        self.stdscr.bkgd(" ", self.color_bg)
        self.stdscr.clear()

        h, w = self.stdscr.getmaxyx()

        # Header
        header_text = " MochiOS Installer "
        self.stdscr.attron(self.color_dialog)
        self.stdscr.addstr(0, 0, header_text + " " * max(0, w - len(header_text)))
        self.stdscr.attroff(self.color_dialog)

        # Footer
        footer_text = " <Tab>/<Arrows>: Navigate  <Enter>: Select "
        self.stdscr.attron(self.color_dialog)
        try:
            self.stdscr.addstr(
                h - 1, 0, footer_text + " " * max(0, w - len(footer_text))
            )
        except curses.error:
            pass  # Ignore error writing to bottom-right corner
        self.stdscr.attroff(self.color_dialog)

        self.stdscr.refresh()

    def _wrap_text(self, text, width):
        lines = []
        for p in text.split("\n"):
            lines.extend(textwrap.wrap(p, width) if p else [""])
        return lines

    def message_box(self, title, text):
        assert self.stdscr is not None
        h, w = self.stdscr.getmaxyx()
        box_width = min(60, w - 4)
        lines = self._wrap_text(text, box_width - 4)

        box_height = len(lines) + 6

        start_y = max(1, (h - box_height) // 2)
        start_x = max(0, (w - box_width) // 2)

        win = curses.newwin(box_height, box_width, start_y, start_x)
        win.bkgd(" ", self.color_dialog)
        win.box()

        title_x = max(0, (box_width - len(title) - 2) // 2)
        win.addstr(0, title_x, f" {title[: box_width - 4]} ")

        for i, line in enumerate(lines):
            win.addstr(i + 2, 2, line)

        button_text = "< OK >"
        btn_y = box_height - 2
        btn_x = (box_width - len(button_text)) // 2
        win.attron(self.color_dialog_hl)
        win.addstr(btn_y, btn_x, button_text)
        win.attroff(self.color_dialog_hl)

        win.refresh()

        while True:
            c = self.stdscr.getch()
            if c in [curses.KEY_ENTER, 10, 13]:
                break

        win.clear()
        self.draw_bg()

    def menu(self, title, options, text=""):
        assert self.stdscr is not None
        h, w = self.stdscr.getmaxyx()
        box_width = min(70, w - 4)

        lines = self._wrap_text(text, box_width - 4) if text else []

        box_height = len(lines) + len(options) + 6
        if text:
            box_height += 1

        start_y = max(1, (h - box_height) // 2)
        start_x = max(0, (w - box_width) // 2)

        win = curses.newwin(box_height, box_width, start_y, start_x)
        win.bkgd(" ", self.color_dialog)
        win.keypad(True)

        current_selection = 0

        while True:
            win.clear()
            win.box()
            title_x = max(0, (box_width - len(title) - 2) // 2)
            win.addstr(0, title_x, f" {title[: box_width - 4]} ")

            y_offset = 2
            if lines:
                for line in lines:
                    win.addstr(y_offset, 2, line)
                    y_offset += 1
                y_offset += 1

            for i, opt in enumerate(options):
                opt_display = opt[: box_width - 8]
                if i == current_selection:
                    win.attron(self.color_dialog_hl)
                    win.addstr(y_offset + i, 4, opt_display)
                    win.attroff(self.color_dialog_hl)
                else:
                    win.addstr(y_offset + i, 4, opt_display)

            win.refresh()

            c = win.getch()
            if c == curses.KEY_UP:
                current_selection = (current_selection - 1) % len(options)
            elif c == curses.KEY_DOWN:
                current_selection = (current_selection + 1) % len(options)
            elif c in [curses.KEY_ENTER, 10, 13]:
                break

        win.clear()
        self.draw_bg()
        return current_selection

    def confirm(self, title, text):
        assert self.stdscr is not None
        h, w = self.stdscr.getmaxyx()
        box_width = min(60, w - 4)
        lines = self._wrap_text(text, box_width - 4)

        box_height = len(lines) + 6

        start_y = max(1, (h - box_height) // 2)
        start_x = max(0, (w - box_width) // 2)

        win = curses.newwin(box_height, box_width, start_y, start_x)
        win.bkgd(" ", self.color_dialog)
        win.keypad(True)

        current_selection = 0
        buttons = ["< Yes >", "< No >"]

        while True:
            win.clear()
            win.box()
            title_x = max(0, (box_width - len(title) - 2) // 2)
            win.addstr(0, title_x, f" {title[: box_width - 4]} ")

            for i, line in enumerate(lines):
                win.addstr(i + 2, 2, line)

            btn_y = box_height - 2
            total_btn_width = sum(len(b) for b in buttons) + 4
            start_btn_x = (box_width - total_btn_width) // 2

            x_offset = start_btn_x
            for i, btn in enumerate(buttons):
                if i == current_selection:
                    win.attron(self.color_dialog_hl)
                    win.addstr(btn_y, x_offset, btn)
                    win.attroff(self.color_dialog_hl)
                else:
                    win.addstr(btn_y, x_offset, btn)
                x_offset += len(btn) + 4

            win.refresh()

            c = win.getch()
            if c in [curses.KEY_LEFT, curses.KEY_UP, 9]:  # 9 is tab
                current_selection = (current_selection - 1) % len(buttons)
            elif c in [curses.KEY_RIGHT, curses.KEY_DOWN]:
                current_selection = (current_selection + 1) % len(buttons)
            elif c in [curses.KEY_ENTER, 10, 13]:
                break

        win.clear()
        self.draw_bg()
        return current_selection == 0

    def input_box(self, title, text, hide=False, default=""):
        assert self.stdscr is not None
        h, w = self.stdscr.getmaxyx()
        box_width = min(60, w - 4)
        lines = self._wrap_text(text, box_width - 4)

        box_height = len(lines) + 7

        start_y = max(1, (h - box_height) // 2)
        start_x = max(0, (w - box_width) // 2)

        win = curses.newwin(box_height, box_width, start_y, start_x)
        win.bkgd(" ", self.color_dialog)
        win.keypad(True)
        curses.curs_set(1)

        user_input = default

        while True:
            win.clear()
            win.box()
            title_x = max(0, (box_width - len(title) - 2) // 2)
            win.addstr(0, title_x, f" {title[: box_width - 4]} ")

            for i, line in enumerate(lines):
                win.addstr(i + 2, 2, line)

            input_y = len(lines) + 3

            # Draw input field bg
            win.attron(self.color_input_bg)
            win.addstr(input_y, 2, " " * (box_width - 4))
            display_str = "*" * len(user_input) if hide else user_input

            max_disp = box_width - 5
            if len(display_str) > max_disp:
                display_str = display_str[-max_disp:]

            win.addstr(input_y, 2, display_str)
            win.attroff(self.color_input_bg)

            # Draw OK button
            btn_y = box_height - 2
            btn_text = "< OK >"
            btn_x = (box_width - len(btn_text)) // 2
            win.attron(self.color_dialog_hl)
            win.addstr(btn_y, btn_x, btn_text)
            win.attroff(self.color_dialog_hl)

            # Move cursor to input field
            win.move(input_y, 2 + len(display_str))

            win.refresh()

            c = win.getch()
            if c in [curses.KEY_ENTER, 10, 13]:
                break
            elif c in [curses.KEY_BACKSPACE, 8, 127]:
                user_input = user_input[:-1]
            elif 32 <= c <= 126:
                user_input += chr(c)

        curses.curs_set(0)
        win.clear()
        self.draw_bg()
        return user_input

    def status_box(self, title, text):
        assert self.stdscr is not None
        h, w = self.stdscr.getmaxyx()
        box_width = min(60, w - 4)
        lines = self._wrap_text(text, box_width - 4)

        box_height = len(lines) + 4

        start_y = max(1, (h - box_height) // 2)
        start_x = max(0, (w - box_width) // 2)

        win = curses.newwin(box_height, box_width, start_y, start_x)
        win.bkgd(" ", self.color_dialog)
        win.box()

        title_x = max(0, (box_width - len(title) - 2) // 2)
        win.addstr(0, title_x, f" {title[: box_width - 4]} ")

        for i, line in enumerate(lines):
            win.addstr(i + 2, 2, line)

        win.refresh()
        return win


tui_app = TUI()


def _tui_wrapper(stdscr, func, *args, **kwargs):
    tui_app.start(stdscr)
    return func(*args, **kwargs)


def run_tui(func, *args, **kwargs):
    """Entry point to start the TUI application."""
    return curses.wrapper(lambda stdscr: _tui_wrapper(stdscr, func, *args, **kwargs))


def init_tui(func):
    """Decorator to run a function within the TUI environment."""

    def wrapper(*args, **kwargs):
        return run_tui(func, *args, **kwargs)

    return wrapper


def show_message(title, text):
    tui_app.message_box(title, text)


def menu_select(options, title="Select an option", text=""):
    idx = tui_app.menu(title, options, text)
    return options[idx], idx


def confirm(title, text):
    return tui_app.confirm(title, text)


def input_text(title, text, default=""):
    return tui_app.input_box(title, text, hide=False, default=default)


def input_password(title, text):
    return tui_app.input_box(title, text, hide=True)


class StatusBox:
    def __init__(self, title, text):
        self.title = title
        self.text = text
        self.win = None

    def __enter__(self):
        self.win = tui_app.status_box(self.title, self.text)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.win:
            self.win.clear()
            tui_app.draw_bg()

    def update(self, text):
        if self.win:
            self.win.clear()
            tui_app.draw_bg()
            self.text = text
            self.win = tui_app.status_box(self.title, self.text)
