import P5
import UIKit

@MainActor
final class ViewController: UITableViewController {
    fileprivate struct Example {
        let title: String
        let summary: String
        let makeSketch: @MainActor @Sendable (CGSize) -> P5Sketch
    }

    private let examples: [Example] = [
        Example(
            title: String(localized: "Fractal tree"),
            summary: String(localized: "Recursive branching and transforms"),
            makeSketch: FractalOrganicTree.init(size:)
        ),
        Example(
            title: String(localized: "Game of Life"),
            summary: String(localized: "A cellular automaton on a pixel grid"),
            makeSketch: GameOfLife.init(size:)
        ),
        Example(
            title: String(localized: "Starfield"),
            summary: String(localized: "Depth and motion from simple geometry"),
            makeSketch: Starfield.init(size:)
        ),
        Example(
            title: String(localized: "Fourier series"),
            summary: String(localized: "Epicycles drawing a periodic wave"),
            makeSketch: FourierSeries.init(size:)
        ),
    ]

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "P5 Gallery")
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Example")
        tableView.accessibilityLabel = String(localized: "Creative coding examples")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        examples.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let example = examples[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Example", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = example.title
        content.secondaryText = example.summary
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityHint = String(localized: "Opens the animated sketch")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let example = examples[indexPath.row]
        navigationController?.pushViewController(
            SketchHostViewController(example: example),
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }
}

@MainActor
private final class SketchHostViewController: UIViewController {
    private let example: ViewController.Example
    private var sketch: P5Sketch?

    init(example: ViewController.Example) {
        self.example = example
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard construction is unsupported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = example.title
        view.backgroundColor = .systemBackground
        installSketch()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateMotion()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sketch?.pause()
    }

    private func installSketch() {
        let availableSize = view.bounds.inset(by: view.safeAreaInsets).size
        let canvasSize = CGSize(
            width: max(availableSize.width, 1),
            height: max(availableSize.height, 1)
        )
        let sketch = example.makeSketch(canvasSize)
        sketch.accessibilityLabel = example.title
        sketch.accessibilityHint = example.summary
        sketch.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sketch.view)
        NSLayoutConstraint.activate([
            sketch.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sketch.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sketch.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sketch.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.sketch = sketch
    }

    @objc private func reduceMotionChanged() {
        updateMotion()
    }

    private func updateMotion() {
        if UIAccessibility.isReduceMotionEnabled {
            sketch?.noLoop()
            sketch?.redraw()
        } else {
            sketch?.loop()
        }
    }
}
