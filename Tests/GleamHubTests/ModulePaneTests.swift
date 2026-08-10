import Foundation
import GleamHub
import Testing

@Suite("Module pane")
struct ModulePaneTests {

  @Test(
    "every destination resolves a pane with a heading and a sentence",
    arguments: HubDestination.allCases)
  func everyDestinationResolvesAPaneWithAHeadingAndASentence(destination: HubDestination) {
    let pane = ModulePaneResolver.pane(for: destination, summaries: makeSummaries())
    #expect(pane.title == destination.title)
    #expect(pane.sentence.hasSuffix("."))
  }

  @Test(
    "a pane carries an action or a not ready note, never both and never neither",
    arguments: HubDestination.allCases
  )
  func aPaneCarriesAnActionOrANotReadyNote(destination: HubDestination) {
    for enabled in [Set<HubModule>(), Set(HubModule.allCases)] {
      let pane = ModulePaneResolver.pane(
        for: destination, summaries: makeSummaries(enabled: enabled))
      #expect((pane.action == nil) == (pane.notReadyNote != nil))
    }
  }

  @Test("an enabled module offers its action", arguments: HubModule.allCases)
  func anEnabledModuleOffersItsAction(module: HubModule) {
    let pane = ModulePaneResolver.pane(
      for: .module(module), summaries: makeSummaries(enabled: [module]))
    #expect(pane.action != nil)
    #expect(pane.action?.title.isEmpty == false)
    #expect(pane.notReadyNote == nil)
  }

  @Test(
    "a module that is not built says so and offers nothing to press", arguments: HubModule.allCases)
  func aModuleThatIsNotBuiltSaysSo(module: HubModule) {
    let pane = ModulePaneResolver.pane(for: .module(module), summaries: makeSummaries())
    #expect(pane.action == nil)
    #expect(pane.notReadyNote?.contains(module.title) == true)
  }

  @Test(
    "a module that is not built still lists the jobs it will run", arguments: HubModule.allCases)
  func aModuleThatIsNotBuiltStillListsItsJobs(module: HubModule) {
    let pane = ModulePaneResolver.pane(for: .module(module), summaries: makeSummaries())
    #expect(pane.jobs.count >= 2)
    for job in pane.jobs {
      #expect(!job.name.isEmpty)
    }
  }

  @Test("no module lists the same job twice", arguments: HubModule.allCases)
  func noModuleListsTheSameJobTwice(module: HubModule) {
    let pane = ModulePaneResolver.pane(for: .module(module), summaries: makeSummaries())
    #expect(Set(pane.jobs.map(\.name)).count == pane.jobs.count)
  }

  @Test("every job carries its own glyph", arguments: HubDestination.allCases)
  func everyJobCarriesItsOwnGlyph(destination: HubDestination) {
    let pane = ModulePaneResolver.pane(for: destination, summaries: makeSummaries())
    for job in pane.jobs {
      #expect(!job.symbolName.isEmpty)
    }
    #expect(Set(pane.jobs.map(\.symbolName)).count == pane.jobs.count)
  }

  @Test("the live figure lands on the first job and nowhere else", arguments: HubModule.allCases)
  func theLiveFigureLandsOnTheFirstJobAndNowhereElse(module: HubModule) {
    let pane = ModulePaneResolver.pane(
      for: .module(module),
      summaries: makeSummaries(enabled: [module], figures: [module: "12.4 GB reclaimable"])
    )
    #expect(pane.jobs.first?.detail == "12.4 GB reclaimable")
    for job in pane.jobs.dropFirst() {
      #expect(job.detail.isEmpty)
    }
  }

  @Test("with no figure yet no job claims one", arguments: HubModule.allCases)
  func withNoFigureYetNoJobClaimsOne(module: HubModule) {
    let pane = ModulePaneResolver.pane(
      for: .module(module), summaries: makeSummaries(enabled: [module]))
    for job in pane.jobs {
      #expect(job.detail.isEmpty)
    }
  }

  @Test("a figure for one module never appears in another module's pane")
  func aFigureForOneModuleNeverLeaksIntoAnother() {
    let all = makeSummaries(
      enabled: Set(HubModule.allCases), figures: [.cleanup: "12.4 GB reclaimable"])
    for module in HubModule.allCases where module != .cleanup {
      let pane = ModulePaneResolver.pane(for: .module(module), summaries: all)
      for job in pane.jobs {
        #expect(!job.detail.contains("12.4 GB"))
      }
    }
  }

  @Test("pane derivation is deterministic", arguments: HubDestination.allCases)
  func paneDerivationIsDeterministic(destination: HubDestination) {
    let all = makeSummaries(enabled: Set(HubModule.allCases), figures: [.cleanup: "1 GB"])
    let first = ModulePaneResolver.pane(for: destination, summaries: all)
    for _ in 1...5 {
      #expect(ModulePaneResolver.pane(for: destination, summaries: all) == first)
    }
  }

  @Test("a summary missing from the list reads as not built", arguments: HubModule.allCases)
  func aSummaryMissingFromTheListReadsAsNotBuilt(module: HubModule) {
    let pane = ModulePaneResolver.pane(for: .module(module), summaries: [])
    #expect(pane.action == nil)
    #expect(pane.notReadyNote != nil)
  }
}
